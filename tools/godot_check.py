#!/usr/bin/env python3
"""Static checks for the Godot project, for sessions where Godot itself cannot run.

    python3 tools/godot_check.py godot/PixelRealm [path/to/extension_api.json]

- every .gd file must parse (gdtoolkit's GDScript 4 grammar)
- names used in code must be declared somewhere (locals, members, inherited members, classes,
  autoloads, Godot classes, utility functions, global constants)
- calls and property reads on values of a known type must exist on that type, with a valid number of
  arguments (project scripts and the Godot 4.3 API from extension_api.json)
- `var x := <Variant>` (inference on a Variant, an error by default in Godot 4)
- a script function overriding a non-virtual engine method, or a member redefining an engine property
- res:// paths in scripts, scenes and project.godot must exist; scene node types and properties
  must exist; $Node paths used by scripts must exist in the scenes those scripts are attached to

Exit status 1 when anything is reported as an ERROR.
"""
import json
import os
import re
import sys

from gdtoolkit.parser import parser
from lark import Token, Tree

PROJ = os.path.abspath(sys.argv[1] if len(sys.argv) > 1 else 'godot/PixelRealm')
API_PATH = sys.argv[2] if len(sys.argv) > 2 else os.path.join(
    '/tmp/claude-0/-home-user-cool/99752c63-9057-5349-b1ad-abd2b562cd69/scratchpad/godot_api', 'extension_api.json')

errors = []
warnings = []


def err(path, line, msg):
    errors.append('%s:%s: ERROR %s' % (os.path.relpath(path, PROJ), line, msg))


def warn(path, line, msg):
    warnings.append('%s:%s: warning %s' % (os.path.relpath(path, PROJ), line, msg))


# ----------------------------------------------------------------------------------------------- the Godot API
API = json.load(open(API_PATH))
GCLASS = {}
for c in API['classes']:
    GCLASS[c['name']] = c
BUILTIN = {c['name']: c for c in API['builtin_classes']}
UTIL = {f['name']: f for f in API['utility_functions']}
SINGLETONS = {s['name']: s['type'] for s in API.get('singletons', [])}
GLOBAL_CONST = {}
for e in API['global_enums']:
    for v in e['values']:
        GLOBAL_CONST[v['name']] = 'int'
    GLOBAL_CONST[e['name']] = 'enum'
for k in ['PI', 'TAU', 'INF', 'NAN']:
    GLOBAL_CONST[k] = 'float'
GD_FUNCS = {'preload': 'Resource', 'load': 'Resource', 'range': 'Array', 'len': 'int', 'char': 'String', 'ord': 'int',
            'convert': 'Variant', 'type_exists': 'bool', 'is_instance_of': 'bool', 'inst_to_dict': 'Dictionary',
            'dict_to_inst': 'Object', 'print_debug': 'void', 'print_stack': 'void', 'get_stack': 'Array',
            'Color8': 'Color', 'assert': 'void'}
BUILTIN_TYPES = set(BUILTIN.keys()) | {'Variant', 'void'}
PACKED_ELEM = {'PackedByteArray': 'int', 'PackedInt32Array': 'int', 'PackedInt64Array': 'int', 'PackedFloat32Array': 'float',
               'PackedFloat64Array': 'float', 'PackedStringArray': 'String', 'PackedVector2Array': 'Vector2',
               'PackedVector3Array': 'Vector3', 'PackedColorArray': 'Color', 'String': 'String'}


def gclass_chain(name):
    out = []
    while name and name in GCLASS:
        out.append(GCLASS[name])
        name = GCLASS[name].get('inherits')
    return out


def gmember(cls, name):
    """('method'|'property'|'signal'|'constant'|'enum', info, type) of a Godot class member, or None"""
    if cls in BUILTIN:
        b = BUILTIN[cls]
        for m in b.get('methods', []):
            if m['name'] == name:
                return ('method', m, m.get('return_type', 'void'))
        for m in b.get('members', []):
            if m['name'] == name:
                return ('property', m, m['type'])
        for m in b.get('constants', []):
            if m['name'] == name:
                return ('constant', m, m['type'])
        for e in b.get('enums', []):
            if e['name'] == name:
                return ('enum', e, 'enum')
            for v in e['values']:
                if v['name'] == name:
                    return ('constant', v, 'int')
        return None
    for c in gclass_chain(cls):
        for m in c.get('methods', []):
            if m['name'] == name:
                rv = m.get('return_value', {}).get('type', 'void')
                return ('method', m, rv)
        for p in c.get('properties', []):
            if p['name'] == name:
                return ('property', p, p['type'].split(',')[0])
        for s in c.get('signals', []):
            if s['name'] == name:
                return ('signal', s, 'Signal')
        for k in c.get('constants', []):
            if k['name'] == name:
                return ('constant', k, 'int')
        for e in c.get('enums', []):
            if e['name'] == name:
                return ('enum', e, 'enum')
            for v in e['values']:
                if v['name'] == name:
                    return ('constant', v, 'int')
    return None


def arg_range(m, builtin=False):
    args = m.get('arguments', [])
    lo = sum(1 for a in args if 'default_value' not in a)
    hi = 999 if m.get('is_vararg') else len(args)
    return lo, hi


# ----------------------------------------------------------------------------------------------- project scripts
class Script:
    def __init__(self, path):
        self.path = path
        self.class_name = None
        self.extends = 'RefCounted'
        self.extends_path = None
        self.vars = {}      # name -> type
        self.consts = {}    # name -> type
        self.enums = {}     # name -> [values]
        self.signals = set()
        self.funcs = {}     # name -> (lo, hi, static, rettype, line)
        self.inner = {}     # name -> Script
        self.tree = None
        self.outer = None
        self.preloads = {}  # const name -> script path


SCRIPTS = {}
CLASSNAMES = {}


def tok(t):
    return t.value if isinstance(t, Token) else None


def line_of(t):
    if isinstance(t, Token):
        return t.line
    if isinstance(t, Tree):
        try:
            return t.meta.line
        except Exception:
            for c in t.children:
                ln = line_of(c)
                if ln:
                    return ln
    return '?'


def type_str(node):
    """the text of a type annotation"""
    if isinstance(node, Token):
        return node.value
    if isinstance(node, Tree):
        parts = []
        for c in node.children:
            parts.append(type_str(c))
        if node.data in ('attribute', 'getattr'):
            return '.'.join(p for p in parts if p != '.')
        s = ''.join(parts)
        return s
    return str(node)


def norm_type(t):
    if t is None:
        return None
    t = t.strip()
    m = re.match(r'^Array\[(.+)\]$', t)
    if m:
        return 'Array[' + m.group(1) + ']'
    return t


def collect(path, tree, sc):
    sc.tree = tree
    for ch in tree.children:
        if not isinstance(ch, Tree):
            continue
        d = ch.data
        if d == 'classname_stmt':
            sc.class_name = tok(ch.children[0])
        elif d == 'extends_stmt':
            v = ch.children[0]
            if isinstance(v, Token) and v.type in ('REGULAR_STRING', 'STRING', 'LONG_STRING') or (isinstance(v, Token) and v.value.startswith('"')):
                sc.extends_path = v.value.strip('"\'')
                sc.extends = None
            else:
                sc.extends = type_str(v)
        elif d in ('class_var_stmt', 'static_class_var_stmt'):
            v = ch.children[0]
            if v.data == 'class_var_stmt':
                v = v.children[0]
            name = tok(v.children[0])
            typ = None
            if v.data in ('class_var_typed', 'class_var_typed_assgnd'):
                typ = norm_type(type_str(v.children[1]))
            elif v.data == 'class_var_inf':
                typ = ('INFER', v.children[1])
            sc.vars[name] = typ
        elif d == 'const_stmt':
            v = ch.children[0]
            name = tok(v.children[0])
            if v.data in ('const_typed_assigned', 'const_typed'):
                sc.consts[name] = norm_type(type_str(v.children[1]))
            else:
                expr = v.children[-1]
                sc.consts[name] = ('INFER', expr)
                pl = find_preload(expr)
                if pl:
                    sc.preloads[name] = pl
        elif d == 'enum_stmt':
            e = ch.children[0]
            if e.data == 'enum_named':
                ename = tok(e.children[0])
                vals = [tok(x.children[0]) for x in e.children[1].children if isinstance(x, Tree)]
                sc.enums[ename] = vals
                for vv in vals:
                    sc.consts[vv] = 'int'
            else:
                for x in e.children[0].children:
                    nm = tok(x.children[0]) if isinstance(x, Tree) and x.children else tok(x)
                    if nm:
                        sc.consts[nm] = 'int'
        elif d == 'signal_stmt':
            sc.signals.add(tok(ch.children[0]))
        elif d in ('func_def', 'static_func_def'):
            fd = ch if d == 'func_def' else ch.children[0]
            hdr = fd.children[0]
            name = tok(hdr.children[0])
            lo = hi = 0
            ret = None
            for hc in hdr.children[1:]:
                if isinstance(hc, Tree) and hc.data == 'func_args':
                    for a in hc.children:
                        hi += 1
                        has_default = any(isinstance(x, Tree) and x.data == 'expr' for x in a.children[1:])
                        if a.data in ('func_arg_regular', 'func_arg_typed') and not has_default:
                            lo += 1
                elif hc is not None:
                    ret = norm_type(type_str(hc))
            sc.funcs[name] = (lo, hi, d == 'static_func_def', ret, line_of(hdr))
        elif d == 'class_def':
            iname = tok(ch.children[0])
            inner = Script(path)
            inner.outer = sc
            body = Tree('start', [c for c in ch.children[1:] if isinstance(c, Tree)])
            for c in ch.children[1:]:
                if isinstance(c, Tree) and c.data == 'extends_stmt':
                    inner.extends = type_str(c.children[0])
            collect(path, body, inner)
            inner.class_name = iname
            sc.inner[iname] = inner


def str_val(node):
    """the text of a string literal node, or None"""
    if isinstance(node, Tree) and node.data == 'string' and node.children:
        node = node.children[0]
    if isinstance(node, Token) and (node.value.startswith('"') or node.value.startswith("'")):
        return node.value.strip('"\'')
    return None


def find_preload(expr):
    if isinstance(expr, Tree):
        if expr.data == 'standalone_call' and tok(expr.children[0]) == 'preload':
            v = str_val(expr.children[1])
            if v:
                return v
        for c in expr.children:
            r = find_preload(c)
            if r:
                return r
    return None


def res_path(p):
    if p.startswith('res://'):
        return os.path.join(PROJ, p[len('res://'):])
    return None


gd_files = []
for root, dirs, files in os.walk(PROJ):
    if '.godot' in root:
        continue
    for f in files:
        if f.endswith('.gd'):
            gd_files.append(os.path.join(root, f))
gd_files.sort()

for path in gd_files:
    src = open(path).read()
    try:
        tree = parser.parse(src, gather_metadata=True)
    except Exception as e:
        msg = str(e).split('\n')[0]
        err(path, '?', 'does not parse: ' + msg)
        continue
    sc = Script(path)
    collect(path, tree, sc)
    SCRIPTS[path] = sc
    if sc.class_name:
        if sc.class_name in CLASSNAMES:
            err(path, 1, 'class_name %s is also used by %s' % (sc.class_name, CLASSNAMES[sc.class_name].path))
        if sc.class_name in GCLASS or sc.class_name in BUILTIN:
            err(path, 1, 'class_name %s hides a Godot class' % sc.class_name)
        CLASSNAMES[sc.class_name] = sc

# autoloads
AUTOLOADS = {}
proj_text = open(os.path.join(PROJ, 'project.godot')).read()
sect = None
for ln in proj_text.split('\n'):
    m = re.match(r'^\[(\w+)\]', ln)
    if m:
        sect = m.group(1)
        continue
    m = re.match(r'^([\w/\.]+)="?\*?(res://[^"]+)"?', ln)
    if m and sect == 'autoload':
        p = res_path(m.group(2))
        if not os.path.exists(p):
            err(os.path.join(PROJ, 'project.godot'), '?', 'autoload %s: missing %s' % (m.group(1), m.group(2)))
        elif p in SCRIPTS:
            AUTOLOADS[m.group(1)] = SCRIPTS[p]
            if SCRIPTS[p].class_name == m.group(1):
                err(p, 1, 'autoload script has class_name equal to its autoload name')
m = re.search(r'run/main_scene="(res://[^"]+)"', proj_text)
if not m or not os.path.exists(res_path(m.group(1))):
    err(os.path.join(PROJ, 'project.godot'), '?', 'main scene missing')
m = re.search(r'config/icon="(res://[^"]+)"', proj_text)
if m and not os.path.exists(res_path(m.group(1))):
    err(os.path.join(PROJ, 'project.godot'), '?', 'icon missing')

# preload consts that point at scripts
for sc in SCRIPTS.values():
    for name, p in list(sc.preloads.items()):
        rp = res_path(p)
        if rp and rp.endswith('.gd') and rp in SCRIPTS:
            sc.consts[name] = ('SCRIPT', SCRIPTS[rp])


def script_of(name):
    """a project class (by class_name), or None"""
    return CLASSNAMES.get(name)


def base_godot(sc):
    """the Godot class at the root of a script's extends chain"""
    seen = 0
    while sc is not None and seen < 20:
        seen += 1
        if sc.extends_path:
            sc = SCRIPTS.get(res_path(sc.extends_path))
            continue
        if sc.extends in CLASSNAMES:
            sc = CLASSNAMES[sc.extends]
            continue
        return sc.extends
    return 'RefCounted'


def script_chain(sc):
    out = []
    seen = 0
    while sc is not None and seen < 20:
        seen += 1
        out.append(sc)
        if sc.extends_path:
            sc = SCRIPTS.get(res_path(sc.extends_path))
        elif sc.extends in CLASSNAMES:
            sc = CLASSNAMES[sc.extends]
        elif sc.outer is not None and sc.extends in sc.outer.inner:
            sc = sc.outer.inner[sc.extends]
        else:
            sc = None
    return out


# ----------------------------------------------------------------------------------------------- types
class Ty:
    """a value type: kind 'inst' (instance of Godot/builtin/script class), 'class' (a class itself),
    'variant' (known to be untyped), 'unknown' (not worked out)"""
    def __init__(self, kind, name=None, script=None, elem=None):
        self.kind = kind
        self.name = name
        self.script = script
        self.elem = elem

    def __repr__(self):
        return '<%s %s>' % (self.kind, self.name)


UNKNOWN = Ty('unknown')
VARIANT = Ty('variant')


def ty_from_name(t, sc=None):
    if t is None:
        return UNKNOWN
    if isinstance(t, tuple):
        return UNKNOWN
    t = t.strip()
    if t == 'Variant':
        return VARIANT
    m = re.match(r'^Array\[(.+)\]$', t)
    if m:
        return Ty('inst', 'Array', elem=ty_from_name(m.group(1), sc))
    if t in BUILTIN or t in GCLASS:
        return Ty('inst', t)
    if t in CLASSNAMES:
        return Ty('inst', t, script=CLASSNAMES[t])
    if sc is not None:
        for s in script_chain(sc):
            if t in s.inner:
                return Ty('inst', t, script=s.inner[t])
            if t in s.enums:
                return Ty('inst', 'int')
        o = sc.outer
        while o is not None:
            if t in o.inner:
                return Ty('inst', t, script=o.inner[t])
            o = o.outer
    if '.' in t:
        a, b = t.split('.', 1)
        if a in CLASSNAMES and b in CLASSNAMES[a].inner:
            return Ty('inst', b, script=CLASSNAMES[a].inner[b])
        if a in CLASSNAMES and b in CLASSNAMES[a].enums:
            return Ty('inst', 'int')
        if a in GCLASS:
            return Ty('inst', 'int')
    return UNKNOWN


def is_variant(t):
    return t.kind == 'variant'


NUMERIC = {'int', 'float'}


# ----------------------------------------------------------------------------------------------- checking
class Ctx:
    def __init__(self, sc, path, static):
        self.sc = sc
        self.path = path
        self.static = static
        self.scopes = [{}]

    def push(self):
        self.scopes.append({})

    def pop(self):
        self.scopes.pop()

    def declare(self, name, ty):
        self.scopes[-1][name] = ty

    def local(self, name):
        for s in reversed(self.scopes):
            if name in s:
                return s[name]
        return None


INFER_STACK = set()


def member_type(sc, name):
    """type of a member of a project script (searching its extends chain); None if not found"""
    for s in script_chain(sc):
        if name in s.vars:
            v = s.vars[name]
            if isinstance(v, tuple):
                key = (s.path, name)
                if key in INFER_STACK:
                    return UNKNOWN
                INFER_STACK.add(key)
                c = Ctx(s, s.path, False)
                t = expr_type(c, v[1], quiet=True)
                INFER_STACK.discard(key)
                return t
            return ty_from_name(v, s) if v else VARIANT
        if name in s.consts:
            v = s.consts[name]
            if isinstance(v, tuple):
                if v[0] == 'SCRIPT':
                    return Ty('class', v[1].class_name or name, script=v[1])
                key = (s.path, name)
                if key in INFER_STACK:
                    return UNKNOWN
                INFER_STACK.add(key)
                c = Ctx(s, s.path, True)
                t = expr_type(c, v[1], quiet=True)
                INFER_STACK.discard(key)
                return t
            return ty_from_name(v, s)
        if name in s.funcs:
            return Ty('inst', 'Callable')
        if name in s.signals:
            return Ty('inst', 'Signal')
        if name in s.enums:
            return Ty('inst', 'Dictionary')
        if name in s.inner:
            return Ty('class', name, script=s.inner[name])
    return None


def find_func(sc, name):
    for s in script_chain(sc):
        if name in s.funcs:
            return s.funcs[name]
    return None


def resolve_name(ctx, name, line, quiet):
    """type of a bare identifier"""
    if name in ('self',):
        return Ty('inst', ctx.sc.class_name or base_godot(ctx.sc), script=ctx.sc)
    if name == 'super':
        chain = list(script_chain(ctx.sc))
        if len(chain) > 1:
            par = chain[1]
            return Ty('inst', par.class_name or base_godot(par), script=par)
        return Ty('inst', base_godot(ctx.sc))
    if name in ('true', 'false'):
        return Ty('inst', 'bool')
    if name == 'null':
        return VARIANT
    lt = ctx.local(name)
    if lt is not None:
        return lt
    mt = member_type(ctx.sc, name)
    if mt is not None:
        return mt
    o = ctx.sc.outer
    while o is not None:
        mt = member_type(o, name)
        if mt is not None and o.consts.get(name) is not None or (o.inner.get(name) is not None):
            return mt
        o = o.outer
    g = gmember(base_godot(ctx.sc), name)
    if g:
        kind, info, typ = g
        if kind == 'method':
            return Ty('inst', 'Callable')
        return ty_from_name(typ)
    if name in CLASSNAMES:
        return Ty('class', name, script=CLASSNAMES[name])
    if name in AUTOLOADS:
        return Ty('inst', name, script=AUTOLOADS[name])
    if name in GCLASS or name in BUILTIN:
        return Ty('class', name)
    if name in SINGLETONS:
        return Ty('inst', SINGLETONS[name])
    if name in GLOBAL_CONST:
        return Ty('inst', 'int') if GLOBAL_CONST[name] == 'int' else (Ty('inst', 'float') if GLOBAL_CONST[name] == 'float' else UNKNOWN)
    if name in UTIL or name in GD_FUNCS:
        return Ty('inst', 'Callable')
    if not quiet:
        err(ctx.path, line, 'unknown name "%s"' % name)
    return UNKNOWN


def lookup_attr(ctx, base, name, line, quiet, calling):
    """type of base.name; reports a missing member when base's type is known"""
    if base.kind in ('unknown', 'variant'):
        return UNKNOWN
    if base.kind == 'class':
        if base.script is not None:
            if name == 'new':
                return Ty('inst', 'Callable')
            t = member_type(base.script, name)
            if t is None:
                if not quiet:
                    err(ctx.path, line, '%s has no member "%s"' % (base.name, name))
                return UNKNOWN
            f = find_func(base.script, name)
            if calling and f is not None and not f[2] and not quiet:
                err(ctx.path, line, '%s.%s() is not static' % (base.name, name))
            return t
        # a Godot class: constants, enums, static methods, new()
        if name == 'new':
            return Ty('inst', 'Callable')
        g = gmember(base.name, name)
        if g is None:
            if not quiet:
                err(ctx.path, line, 'Godot class %s has no member "%s"' % (base.name, name))
            return UNKNOWN
        kind, info, typ = g
        if kind == 'method':
            return Ty('inst', 'Callable')
        return ty_from_name(typ) if kind != 'enum' else Ty('inst', 'Dictionary')
    # an instance
    if base.script is not None:
        t = member_type(base.script, name)
        if t is not None:
            return t
        g = gmember(base_godot(base.script), name)
        if g is None:
            if not quiet:
                err(ctx.path, line, '%s has no member "%s"' % (base.name, name))
            return UNKNOWN
        kind, info, typ = g
        if kind == 'method':
            return Ty('inst', 'Callable')
        return ty_from_name(typ)
    if base.name == 'Dictionary':
        g = gmember('Dictionary', name)
        if g:
            return Ty('inst', 'Callable') if g[0] == 'method' else ty_from_name(g[2])
        return VARIANT
    g = gmember(base.name, name)
    if g is None:
        if base.name in ('Object',):
            return UNKNOWN
        if not quiet:
            err(ctx.path, line, '%s has no member "%s"' % (base.name, name))
        return UNKNOWN
    kind, info, typ = g
    if kind == 'method':
        return Ty('inst', 'Callable')
    if kind == 'enum':
        return Ty('inst', 'Dictionary')
    return ty_from_name(typ)


def method_call(ctx, base, name, nargs, line, quiet):
    """return type of base.name(args); checks it exists and the argument count"""
    if base.kind in ('unknown', 'variant'):
        return UNKNOWN
    if base.kind == 'class' and name == 'new':
        if base.script is not None:
            f = find_func(base.script, '_init')
            if f and not quiet and not (f[0] <= nargs <= f[1]):
                err(ctx.path, line, '%s.new() takes %d..%d arguments, given %d' % (base.name, f[0], f[1], nargs))
            return Ty('inst', base.name, script=base.script)
        return Ty('inst', base.name)
    scr = base.script
    if scr is not None:
        f = find_func(scr, name)
        if f is not None:
            lo, hi, static, ret, _ = f
            if base.kind == 'class' and not static and not quiet:
                err(ctx.path, line, '%s.%s() is not static' % (base.name, name))
            if not quiet and not (lo <= nargs <= hi):
                err(ctx.path, line, '%s() takes %d..%d arguments, given %d' % (name, lo, hi, nargs))
            if ret is None:
                return UNKNOWN
            return ty_from_name(ret, scr) if ret != 'void' else Ty('inst', 'void')
        mt = member_type(scr, name)
        if mt is not None:
            return UNKNOWN
        gname = base_godot(scr)
        if base.kind == 'class':
            if not quiet:
                err(ctx.path, line, '%s has no static function "%s"' % (base.name, name))
            return UNKNOWN
    else:
        gname = base.name
    if gname == 'Dictionary' and gmember('Dictionary', name) is None:
        return UNKNOWN
    g = gmember(gname, name)
    if g is None or g[0] != 'method':
        if g is not None and g[0] in ('property',) and g[2] == 'Callable':
            return UNKNOWN
        if not quiet:
            err(ctx.path, line, '%s has no method "%s"' % (base.name if scr is None else (base.name or gname), name))
        return UNKNOWN
    kind, info, typ = g
    lo, hi = arg_range(info)
    if not quiet and not (lo <= nargs <= hi):
        err(ctx.path, line, '%s.%s() takes %d..%d arguments, given %d' % (gname, name, lo, hi, nargs))
    if typ == 'Variant':
        return VARIANT
    if gname in ('Array',) and base.elem is not None and name in ('pop_back', 'pop_front', 'front', 'back', 'pick_random', 'get', 'max', 'min'):
        return base.elem
    return ty_from_name(typ)


def lit_type(t):
    if t.type in ('NUMBER',):
        v = t.value
        if re.match(r'^-?(0x[0-9a-fA-F_]+|0b[01_]+|[0-9_]+)$', v):
            return Ty('inst', 'int')
        return Ty('inst', 'float')
    if 'STRING' in t.type or t.value.startswith('"') or t.value.startswith("'"):
        return Ty('inst', 'String')
    return None


def binary_type(a, b, op):
    if op in ('==', '!=', '<', '>', '<=', '>=', 'and', 'or', 'in', 'not in', 'is', '&&', '||'):
        return Ty('inst', 'bool')
    if a.kind != 'inst' or b.kind != 'inst':
        if a.kind == 'variant' or b.kind == 'variant':
            return VARIANT
        return UNKNOWN
    if a.name in NUMERIC and b.name in NUMERIC:
        if op in ('&', '|', '^', '<<', '>>', '%') and a.name == 'int' and b.name == 'int':
            return Ty('inst', 'int')
        if a.name == 'int' and b.name == 'int':
            return Ty('inst', 'int')
        return Ty('inst', 'float')
    if a.name == 'String':
        return Ty('inst', 'String')
    if a.name in BUILTIN and a.name not in NUMERIC:
        return Ty('inst', a.name)
    if b.name in BUILTIN and b.name not in NUMERIC and a.name in NUMERIC:
        return Ty('inst', b.name)
    return UNKNOWN


def call_args(node):
    return [c for c in node.children[1:]]


def expr_type(ctx, node, quiet=False):
    """type of an expression, reporting problems found inside it"""
    if isinstance(node, Token):
        lt = lit_type(node)
        if lt is not None:
            return lt
        if node.type == 'NAME':
            return resolve_name(ctx, node.value, node.line, quiet)
        return UNKNOWN
    if not isinstance(node, Tree):
        return UNKNOWN
    d = node.data
    if d == 'expr':
        return expr_type(ctx, node.children[0], quiet) if node.children else UNKNOWN
    if d in ('array',):
        for c in node.children:
            expr_type(ctx, c, quiet)
        return Ty('inst', 'Array')
    if d in ('dict',):
        for c in node.children:
            if isinstance(c, Tree):
                for cc in c.children:
                    if isinstance(cc, Tree) or (isinstance(cc, Token) and cc.type != 'NAME'):
                        expr_type(ctx, cc, quiet)
        return Ty('inst', 'Dictionary')
    if d == 'string':
        return Ty('inst', 'String')
    if d in ('string_name',):
        return Ty('inst', 'StringName')
    if d in ('node_path',):
        return Ty('inst', 'NodePath')
    if d in ('get_node', 'get_node_path'):
        return Ty('inst', 'Node')
    if d == 'lambda':
        check_lambda(ctx, node)
        return Ty('inst', 'Callable')
    if d == 'standalone_call':
        fname = node.children[0]
        args = call_args(node)
        for a in args:
            expr_type(ctx, a, quiet)
        name = tok(fname)
        line = line_of(fname)
        if name is None:
            return UNKNOWN
        if name in BUILTIN:
            return Ty('inst', name)
        lt = ctx.local(name)
        if lt is not None:
            return UNKNOWN
        f = find_func(ctx.sc, name)
        if f is not None:
            lo, hi, static, ret, _ = f
            if not quiet and not (lo <= len(args) <= hi):
                err(ctx.path, line, '%s() takes %d..%d arguments, given %d' % (name, lo, hi, len(args)))
            if ctx.static and not static and not quiet:
                err(ctx.path, line, 'calling non-static %s() from a static function' % name)
            if ret is None:
                return UNKNOWN
            return ty_from_name(ret, ctx.sc) if ret != 'void' else Ty('inst', 'void')
        o = ctx.sc.outer
        while o is not None:
            f = find_func(o, name)
            if f is not None and f[2]:
                return ty_from_name(f[3], o) if f[3] else UNKNOWN
            o = o.outer
        g = gmember(base_godot(ctx.sc), name)
        if g is not None and g[0] == 'method':
            lo, hi = arg_range(g[1])
            if not quiet and not (lo <= len(args) <= hi):
                err(ctx.path, line, '%s() takes %d..%d arguments, given %d' % (name, lo, hi, len(args)))
            if ctx.static and not quiet and not g[1].get('is_static'):
                err(ctx.path, line, 'calling instance method %s() from a static function' % name)
            return ty_from_name(g[2]) if g[2] != 'Variant' else VARIANT
        if name in GD_FUNCS:
            if name == 'preload' and args and str_val(args[0]):
                p = res_path(str_val(args[0]))
                if p and not os.path.exists(p) and not quiet:
                    err(ctx.path, line, 'preload of a missing file ' + str_val(args[0]))
                if p and p.endswith('.gd') and p in SCRIPTS:
                    return Ty('class', SCRIPTS[p].class_name or 'script', script=SCRIPTS[p])
                if p and p.endswith('.tscn'):
                    return Ty('inst', 'PackedScene')
                if p and p.endswith('.png'):
                    return Ty('inst', 'Texture2D')
            if name == 'load' and args and str_val(args[0]) and str_val(args[0]).startswith('res://'):
                p = res_path(str_val(args[0]))
                if p and not os.path.exists(p) and '%' not in str_val(args[0]) and not quiet:
                    err(ctx.path, line, 'load of a missing file ' + str_val(args[0]))
            r = GD_FUNCS[name]
            return VARIANT if r == 'Variant' else Ty('inst', r)
        if name in UTIL:
            u = UTIL[name]
            lo, hi = arg_range(u)
            if not quiet and not (lo <= len(args) <= hi):
                err(ctx.path, line, '%s() takes %d..%d arguments, given %d' % (name, lo, hi, len(args)))
            rt = u.get('return_type', 'void')
            return VARIANT if rt == 'Variant' else Ty('inst', rt)
        if name in ('super',):
            return UNKNOWN
        if name in GCLASS:
            return Ty('inst', name)
        if not quiet:
            err(ctx.path, line, 'unknown function "%s()"' % name)
        return UNKNOWN
    if d in ('getattr', 'getattr_call'):
        return attr_chain(ctx, node, quiet)
    if d == 'subscr_expr':
        base = expr_type(ctx, node.children[0], quiet)
        for c in node.children[1:]:
            expr_type(ctx, c, quiet)
        if base.kind == 'inst':
            if base.name in PACKED_ELEM:
                return Ty('inst', PACKED_ELEM[base.name])
            if base.name == 'Array':
                return base.elem if base.elem is not None else VARIANT
            if base.name == 'Dictionary':
                return VARIANT
            if base.name in ('Vector2', 'Vector3', 'Vector4', 'Color', 'Quaternion'):
                return Ty('inst', 'float')
            if base.name in ('Vector2i', 'Vector3i', 'Vector4i'):
                return Ty('inst', 'int')
        if base.kind == 'variant':
            return VARIANT
        return UNKNOWN
    if d in ('arith_expr', 'mdr_expr', 'bitw_or', 'bitw_xor', 'bitw_and', 'shift_expr', 'comparison', 'and_test', 'or_test',
             'content_test', 'type_test', 'type_cast', 'actual_type_cast', 'pow_expr', 'operator_expr'):
        ch = node.children
        if d in ('type_cast', 'actual_type_cast'):
            expr_type(ctx, ch[0], quiet)
            return ty_from_name(type_str(ch[-1]), ctx.sc)
        if d == 'type_test':
            expr_type(ctx, ch[0], quiet)
            return Ty('inst', 'bool')
        cur = expr_type(ctx, ch[0], quiet)
        i = 1
        while i < len(ch):
            op = tok(ch[i]) if isinstance(ch[i], Token) else None
            if op is None:
                cur = binary_type(cur, expr_type(ctx, ch[i], quiet), '?')
                i += 1
                continue
            rhs = expr_type(ctx, ch[i + 1], quiet) if i + 1 < len(ch) else UNKNOWN
            cur = binary_type(cur, rhs, op)
            i += 2
        if d in ('comparison', 'and_test', 'or_test', 'content_test'):
            return Ty('inst', 'bool')
        return cur
    if d in ('not_test', 'asless_actual_not_test', 'actual_not_test'):
        for c in node.children:
            if isinstance(c, Tree) or (isinstance(c, Token) and c.type == 'NAME'):
                expr_type(ctx, c, quiet)
        return Ty('inst', 'bool')
    if d in ('neg_expr', 'bitw_not', 'unary_expr', 'asless_actual_neg_expr', 'actual_neg_expr', 'asless_actual_bitw_not', 'actual_bitw_not'):
        t = UNKNOWN
        for c in node.children:
            if isinstance(c, Tree) or (isinstance(c, Token) and c.type in ('NAME', 'NUMBER')):
                t = expr_type(ctx, c, quiet)
        return t
    if d in ('test_expr', 'ternary_expr'):
        ch = [c for c in node.children if not (isinstance(c, Token) and c.value in ('if', 'else'))]
        a = expr_type(ctx, ch[0], quiet)
        expr_type(ctx, ch[1], quiet)
        b = expr_type(ctx, ch[2], quiet)
        if a.kind == 'inst' and b.kind == 'inst':
            if a.name == b.name:
                return a
            return VARIANT
        if a.kind == 'variant' or b.kind == 'variant':
            return VARIANT
        return UNKNOWN
    if d == 'await_expr':
        for c in node.children:
            if isinstance(c, Tree):
                expr_type(ctx, c, quiet)
        return VARIANT
    if d == 'par_expr':
        return expr_type(ctx, node.children[0], quiet)
    if d == 'assnmnt_expr':
        expr_type(ctx, node.children[0], quiet)
        expr_type(ctx, node.children[-1], quiet)
        return Ty('inst', 'void')
    for c in node.children:
        if isinstance(c, Tree):
            expr_type(ctx, c, quiet)
    return UNKNOWN


def attr_chain(ctx, node, quiet):
    """getattr / getattr_call: base . name . name ... (call args after the getattr)"""
    if node.data == 'getattr_call':
        ga = node.children[0]
        args = node.children[1:]
        for a in args:
            expr_type(ctx, a, quiet)
        parts = flatten_getattr(ga)
        base_t = expr_type(ctx, parts[0], quiet)
        names = parts[1:]
        for nm in names[:-1]:
            base_t = lookup_attr(ctx, base_t, tok(nm), line_of(nm), quiet, False)
        last = names[-1]
        name = tok(last)
        if name in ('emit', 'connect', 'disconnect', 'is_connected', 'call', 'callv', 'bind', 'call_deferred', 'bindv', 'unbind') \
                and base_t.kind == 'inst' and base_t.name in ('Signal', 'Callable'):
            return method_call(ctx, base_t, name, len(args), line_of(last), quiet)
        return method_call(ctx, base_t, name, len(args), line_of(last), quiet)
    parts = flatten_getattr(node)
    base_t = expr_type(ctx, parts[0], quiet)
    for nm in parts[1:]:
        base_t = lookup_attr(ctx, base_t, tok(nm), line_of(nm), quiet, False)
    return base_t


def flatten_getattr(ga):
    out = []
    for c in ga.children:
        if isinstance(c, Token) and c.value == '.':
            continue
        out.append(c)
    return out


def check_lambda(ctx, node):
    hdr = node.children[0]
    ctx.push()
    for c in hdr.children:
        if isinstance(c, Tree) and c.data == 'func_args':
            for a in c.children:
                nm = tok(a.children[0])
                ty = ty_from_name(type_str(a.children[1]), ctx.sc) if a.data == 'func_arg_typed' else VARIANT
                ctx.declare(nm, ty)
    for st in node.children[1:]:
        check_stmt(ctx, st)
    ctx.pop()


def declare_var(ctx, v, line):
    name = tok(v.children[0])
    d = v.data
    if d in ('func_var_typed', 'func_var_typed_assgnd'):
        ty = ty_from_name(type_str(v.children[1]), ctx.sc)
        if d == 'func_var_typed_assgnd':
            expr_type(ctx, v.children[2])
    elif d == 'func_var_inf':
        ty = expr_type(ctx, v.children[1])
        if ty.kind == 'variant':
            err(ctx.path, line, 'var %s := ... infers from a Variant value (give it a type)' % name)
        if ty.kind == 'inst' and ty.name == 'void':
            err(ctx.path, line, 'var %s := ... gets its value from a function that returns nothing' % name)
    elif d == 'func_var_assigned':
        expr_type(ctx, v.children[1])
        ty = VARIANT
    else:
        ty = VARIANT
    ctx.declare(name, ty)


def check_stmt(ctx, st):
    if isinstance(st, Token):
        return
    d = st.data
    line = line_of(st)
    if d == 'func_var_stmt':
        declare_var(ctx, st.children[0], line)
    elif d == 'const_stmt':
        v = st.children[0]
        nm = tok(v.children[0])
        ty = expr_type(ctx, v.children[-1])
        ctx.declare(nm, ty)
    elif d in ('expr_stmt', 'return_stmt'):
        for c in st.children:
            if isinstance(c, Tree):
                expr_type(ctx, c)
    elif d in ('pass_stmt', 'continue_stmt', 'break_stmt', 'breakpoint_stmt', 'annotation'):
        return
    elif d in ('if_stmt',):
        for br in st.children:
            ctx.push()
            for c in br.children:
                if isinstance(c, Tree) and c.data == 'expr':
                    expr_type(ctx, c)
                else:
                    check_stmt(ctx, c)
            ctx.pop()
    elif d == 'while_stmt':
        expr_type(ctx, st.children[0])
        ctx.push()
        for c in st.children[1:]:
            check_stmt(ctx, c)
        ctx.pop()
    elif d in ('for_stmt', 'for_stmt_typed'):
        nm = tok(st.children[0])
        ctx.push()
        if d == 'for_stmt_typed':
            ctx.declare(nm, ty_from_name(type_str(st.children[1]), ctx.sc))
            it = expr_type(ctx, st.children[2])
            body = st.children[3:]
        else:
            it = expr_type(ctx, st.children[1])
            et = UNKNOWN
            if it.kind == 'inst':
                if it.name == 'int':
                    et = Ty('inst', 'int')
                elif it.name in PACKED_ELEM:
                    et = Ty('inst', PACKED_ELEM[it.name])
                elif it.name == 'Array':
                    et = it.elem if it.elem is not None else VARIANT
                elif it.name == 'Dictionary':
                    et = VARIANT
            elif it.kind == 'variant':
                et = VARIANT
            ctx.declare(nm, et)
            body = st.children[2:]
        for c in body:
            check_stmt(ctx, c)
        ctx.pop()
    elif d == 'match_stmt':
        expr_type(ctx, st.children[0])
        for br in st.children[1:]:
            ctx.push()
            for c in br.children:
                if isinstance(c, Tree) and c.data == 'pattern':
                    for p in c.iter_subtrees():
                        if p.data == 'var_capture_pattern':
                            ctx.declare(tok(p.children[0]), VARIANT)
                    continue
                check_stmt(ctx, c)
            ctx.pop()
    elif d == 'func_var_empty':
        ctx.declare(tok(st.children[0]), VARIANT)
    else:
        for c in st.children:
            if isinstance(c, Tree):
                if c.data == 'expr':
                    expr_type(ctx, c)
                else:
                    check_stmt(ctx, c)


def check_function(sc, path, fdef, static):
    hdr = fdef.children[0]
    ctx = Ctx(sc, path, static)
    for c in hdr.children[1:]:
        if isinstance(c, Tree) and c.data == 'func_args':
            for a in c.children:
                nm = tok(a.children[0])
                if a.data in ('func_arg_typed', 'func_arg_typed_dflt'):
                    ty = ty_from_name(type_str(a.children[1]), sc)
                elif a.data == 'func_arg_inf':
                    ty = expr_type(ctx, a.children[1])
                else:
                    ty = VARIANT
                for dc in a.children[1:]:
                    if isinstance(dc, Tree) and dc.data == 'expr':
                        expr_type(ctx, dc)
                ctx.declare(nm, ty)
    ctx.push()
    for st in fdef.children[1:]:
        check_stmt(ctx, st)
    ctx.pop()


def check_script(sc):
    path = sc.path
    base = base_godot(sc)
    if base not in GCLASS and base not in ('RefCounted',) and not sc.extends_path:
        if sc.extends not in CLASSNAMES and (sc.outer is None or sc.extends not in sc.outer.inner):
            err(path, 1, 'extends unknown class %s' % sc.extends)
    # members that clash with the engine class
    for name in list(sc.vars.keys()) + [k for k, v in sc.consts.items()] + list(sc.signals):
        g = gmember(base, name)
        if g is not None:
            err(path, '?', 'member "%s" redefines %s.%s' % (name, base, name))
    for name, f in sc.funcs.items():
        g = gmember(base, name)
        if g is not None and g[0] == 'method' and not g[1].get('is_virtual'):
            err(path, f[4], 'function %s() overrides a non-virtual %s method' % (name, base))
    # inferred members
    for name, v in sc.vars.items():
        if isinstance(v, tuple):
            ctx = Ctx(sc, path, False)
            t = expr_type(ctx, v[1])
            if t.kind == 'variant':
                err(path, line_of(v[1]), 'var %s := ... infers from a Variant value' % name)
    for name, v in sc.consts.items():
        if isinstance(v, tuple) and v[0] == 'INFER':
            ctx = Ctx(sc, path, True)
            expr_type(ctx, v[1])
    for ch in sc.tree.children:
        if not isinstance(ch, Tree):
            continue
        if ch.data == 'func_def':
            check_function(sc, path, ch, False)
        elif ch.data == 'static_func_def':
            check_function(sc, path, ch.children[0], True)
        elif ch.data == 'class_def':
            iname = tok(ch.children[0])
            inner = sc.inner[iname]
            check_script(inner)


for sc in list(SCRIPTS.values()):
    check_script(sc)


# ----------------------------------------------------------------------------------------------- scenes
def parse_tscn(path):
    nodes = []
    exts = {}
    subs = {}
    cur = None
    for i, ln in enumerate(open(path).read().split('\n'), 1):
        m = re.match(r'^\[ext_resource (.*)\]$', ln)
        if m:
            attrs = dict(re.findall(r'(\w+)="([^"]*)"', m.group(1)))
            exts[attrs.get('id')] = attrs
            p = res_path(attrs.get('path', ''))
            if not p or not os.path.exists(p):
                err(path, i, 'ext_resource missing: %s' % attrs.get('path'))
            continue
        m = re.match(r'^\[sub_resource (.*)\]$', ln)
        if m:
            attrs = dict(re.findall(r'(\w+)="([^"]*)"', m.group(1)))
            subs[attrs.get('id')] = attrs
            if attrs.get('type') not in GCLASS:
                err(path, i, 'unknown sub_resource type %s' % attrs.get('type'))
            cur = ('sub', attrs.get('type'))
            continue
        m = re.match(r'^\[node (.*)\]$', ln)
        if m:
            attrs = dict(re.findall(r'(\w+)="([^"]*)"', m.group(1)))
            inst = re.search(r'instance=ExtResource\("([^"]+)"\)', m.group(1))
            node = {'name': attrs.get('name'), 'type': attrs.get('type'), 'parent': attrs.get('parent'), 'line': i,
                    'script': None, 'instance': inst.group(1) if inst else None}
            if node['type'] and node['type'] not in GCLASS:
                err(path, i, 'unknown node type %s' % node['type'])
            if inst and inst.group(1) not in exts:
                err(path, i, 'instance of unknown ext_resource %s' % inst.group(1))
            nodes.append(node)
            cur = ('node', node)
            continue
        m = re.match(r'^\[(resource|gd_scene|gd_resource|connection)', ln)
        if m:
            cur = None
            if m.group(1) == 'connection':
                pass
            continue
        m = re.match(r'^([\w/]+) = (.*)$', ln)
        if m and cur is not None:
            prop, val = m.group(1), m.group(2)
            for ref in re.findall(r'ExtResource\("([^"]+)"\)', val):
                if ref not in exts:
                    err(path, i, 'unknown ExtResource %s' % ref)
            for ref in re.findall(r'SubResource\("([^"]+)"\)', val):
                if ref not in subs:
                    err(path, i, 'unknown SubResource %s' % ref)
            if cur[0] == 'node':
                node = cur[1]
                if prop == 'script':
                    ref = re.findall(r'ExtResource\("([^"]+)"\)', val)
                    if ref and ref[0] in exts:
                        node['script'] = res_path(exts[ref[0]]['path'])
                    continue
                ntype = node['type']
                if ntype and '/' not in prop and prop not in ('metadata',) and gmember(ntype, prop) is None:
                    err(path, i, '%s has no property "%s"' % (ntype, prop))
            elif cur[0] == 'sub':
                if '/' not in prop and gmember(cur[1], prop) is None:
                    err(path, i, '%s has no property "%s"' % (cur[1], prop))
    return nodes, exts


def node_paths(nodes):
    """full paths from the scene root: '.', 'A', 'A/B'"""
    out = {}
    for n in nodes:
        if n['parent'] is None:
            out['.'] = n
        else:
            p = n['name'] if n['parent'] == '.' else n['parent'] + '/' + n['name']
            out[p] = n
    return out


for root, dirs, files in os.walk(PROJ):
    if '.godot' in root:
        continue
    for f in files:
        if not f.endswith('.tscn'):
            continue
        path = os.path.join(root, f)
        nodes, exts = parse_tscn(path)
        paths = node_paths(nodes)
        for n in nodes:
            if n['parent'] is not None and n['parent'] != '.' and n['parent'] not in paths:
                err(path, n['line'], 'parent %s not found' % n['parent'])
        # $Node paths used by the scripts attached here
        for p, n in paths.items():
            sp = n['script']
            if not sp or sp not in SCRIPTS:
                continue
            src = open(sp).read()
            for m in re.finditer(r'\$([A-Za-z_][\w/]*)|get_node\("([^"]+)"\)', src):
                rel = m.group(1) or m.group(2)
                full = rel if p == '.' else p + '/' + rel
                if full not in paths and not any(k.startswith(full) for k in paths):
                    err(sp, '?', '$%s is not in %s' % (rel, os.path.relpath(path, PROJ)))

for path in gd_files:
    src = open(path).read()
    for m in re.finditer(r'"(res://[^"%]+)"', src):
        p = res_path(m.group(1))
        if p and not os.path.exists(p):
            err(path, src[:m.start()].count('\n') + 1, 'missing file %s' % m.group(1))

for e in errors:
    print(e)
for w in warnings[:50]:
    print(w)
print('%d scripts checked: %d errors, %d warnings' % (len(gd_files), len(errors), len(warnings)))
sys.exit(1 if errors else 0)
