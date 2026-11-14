// The renderer: WebGL 2, one shader, quads batched by texture. Positions are screen pixels (the top
// left is 0,0), colours are 32-bit RGBA made by rgba(). The texture sheet (the atlas) holds every
// picture; land sections and the light have textures of their own.

const Atlas = { w: DATA.atlas.w, h: DATA.atlas.h, px: null, px32: null, tex: null, orig: null };
const rgba = (hex, a = 1) => (((Math.max(0, Math.min(1, a)) * 255) << 24) | ((hex & 255) << 16) | (hex & 0xFF00) | ((hex >> 16) & 255)) >>> 0;
const WHITE = 0xFFFFFFFF;
const grey = (v, a = 1) => { const c = Math.floor(clampD(v, 0, 1) * 255); return (((a * 255) << 24) | (c << 16) | (c << 8) | c) >>> 0; };

const R = {
	canvas: null, gl: null, W: 0, H: 0, dpr: 1,
	MAXQ: 8192, n: 0, tex: null, blendMode: 0, draws: 0, quads: 0,
	m: [1, 0, 0, 1, 0, 0], stack: [], ident: true,
	// uv of the white square and the round dot kept in the atlas
	wu: 0, wv: 0, cu0: 0, cv0: 0, cu1: 0, cv1: 0,

	init(canvas) {
		this.canvas = canvas;
		const gl = canvas.getContext("webgl2", { antialias: false, alpha: false, premultipliedAlpha: false, powerPreference: "high-performance" });
		if (!gl) return false;
		this.gl = gl;
		const vs = `#version 300 es
layout(location=0) in vec2 a_pos;
layout(location=1) in vec2 a_uv;
layout(location=2) in vec4 a_col;
layout(location=3) in float a_add;
uniform vec2 u_res;
out vec2 v_uv; out vec4 v_col; out float v_add;
void main() { gl_Position = vec4(a_pos.x / u_res.x * 2.0 - 1.0, 1.0 - a_pos.y / u_res.y * 2.0, 0.0, 1.0); v_uv = a_uv; v_col = a_col; v_add = a_add; }`;
		const fs = `#version 300 es
precision mediump float;
in vec2 v_uv; in vec4 v_col; in float v_add;
uniform sampler2D u_tex;
out vec4 o;
void main() { vec4 t = texture(u_tex, v_uv); t.rgb = mix(t.rgb, vec3(1.0), v_add); o = t * v_col; if (o.a < 0.004) discard; }`;
		const sh = (type, src) => { const s = gl.createShader(type); gl.shaderSource(s, src); gl.compileShader(s); if (!gl.getShaderParameter(s, gl.COMPILE_STATUS)) throw new Error(gl.getShaderInfoLog(s)); return s; };
		const p = gl.createProgram();
		gl.attachShader(p, sh(gl.VERTEX_SHADER, vs)); gl.attachShader(p, sh(gl.FRAGMENT_SHADER, fs)); gl.linkProgram(p);
		if (!gl.getProgramParameter(p, gl.LINK_STATUS)) throw new Error(gl.getProgramInfoLog(p));
		gl.useProgram(p);
		this.uRes = gl.getUniformLocation(p, "u_res");
		gl.uniform1i(gl.getUniformLocation(p, "u_tex"), 0);
		// a vertex: x, y, u, v (floats), colour (4 bytes), add (float): 24 bytes
		this.buf = new ArrayBuffer(this.MAXQ * 4 * 24);
		this.f32 = new Float32Array(this.buf); this.u32 = new Uint32Array(this.buf);
		this.vao = gl.createVertexArray(); gl.bindVertexArray(this.vao);
		this.vbo = gl.createBuffer(); gl.bindBuffer(gl.ARRAY_BUFFER, this.vbo);
		gl.bufferData(gl.ARRAY_BUFFER, this.buf.byteLength, gl.DYNAMIC_DRAW);
		gl.enableVertexAttribArray(0); gl.vertexAttribPointer(0, 2, gl.FLOAT, false, 24, 0);
		gl.enableVertexAttribArray(1); gl.vertexAttribPointer(1, 2, gl.FLOAT, false, 24, 8);
		gl.enableVertexAttribArray(2); gl.vertexAttribPointer(2, 4, gl.UNSIGNED_BYTE, true, 24, 16);
		gl.enableVertexAttribArray(3); gl.vertexAttribPointer(3, 1, gl.FLOAT, false, 24, 20);
		const idx = new Uint16Array(this.MAXQ * 6);
		for (let i = 0, v = 0; i < idx.length; i += 6, v += 4) { idx[i] = v; idx[i + 1] = v + 1; idx[i + 2] = v + 2; idx[i + 3] = v + 2; idx[i + 4] = v + 1; idx[i + 5] = v + 3; }
		this.ibo = gl.createBuffer(); gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, this.ibo); gl.bufferData(gl.ELEMENT_ARRAY_BUFFER, idx, gl.STATIC_DRAW);
		gl.enable(gl.BLEND); gl.blendFunc(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA);
		gl.activeTexture(gl.TEXTURE0);
		return true;
	},
	makeTex(w, h, pixels, linear) {
		const gl = this.gl, t = gl.createTexture();
		gl.bindTexture(gl.TEXTURE_2D, t);
		const f = linear ? gl.LINEAR : gl.NEAREST;
		gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, f); gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, f);
		gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE); gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE);
		gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA, w, h, 0, gl.RGBA, gl.UNSIGNED_BYTE, pixels);
		this.tex = null;
		return { t, w, h };
	},
	updateTex(tex, w, h, pixels) {
		const gl = this.gl;
		this.flush();
		gl.bindTexture(gl.TEXTURE_2D, tex.t);
		if (w !== tex.w || h !== tex.h) { gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA, w, h, 0, gl.RGBA, gl.UNSIGNED_BYTE, pixels); tex.w = w; tex.h = h; }
		else gl.texSubImage2D(gl.TEXTURE_2D, 0, 0, 0, w, h, gl.RGBA, gl.UNSIGNED_BYTE, pixels);
		this.tex = null;
	},
	/** a part of a texture changed (x, y, w, h in its pixels) */
	updateTexRect(tex, x, y, w, h, pixels) {
		const gl = this.gl;
		this.flush();
		gl.bindTexture(gl.TEXTURE_2D, tex.t);
		gl.texSubImage2D(gl.TEXTURE_2D, 0, x, y, w, h, gl.RGBA, gl.UNSIGNED_BYTE, pixels);
		this.tex = null;
	},
	freeTex(tex) { this.gl.deleteTexture(tex.t); },
	resize() {
		const dpr = Math.min(window.devicePixelRatio || 1, 3);
		const cw = window.innerWidth, chh = window.innerHeight;
		this.dpr = dpr;
		this.canvas.width = Math.max(1, Math.round(cw * dpr)); this.canvas.height = Math.max(1, Math.round(chh * dpr));
		this.W = this.canvas.width; this.H = this.canvas.height;
	},
	begin(r, g, b) {
		const gl = this.gl;
		gl.viewport(0, 0, this.W, this.H);
		gl.uniform2f(this.uRes, this.W, this.H);
		gl.clearColor(r, g, b, 1); gl.clear(gl.COLOR_BUFFER_BIT);
		this.n = 0; this.tex = null; this.draws = 0; this.quads = 0; this.blendMode = 0;
		gl.blendFunc(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA);
		this.m = [1, 0, 0, 1, 0, 0]; this.stack.length = 0; this.ident = true;
	},
	flush() {
		if (!this.n) return;
		const gl = this.gl;
		gl.bindVertexArray(this.vao);
		gl.bindBuffer(gl.ARRAY_BUFFER, this.vbo);
		gl.bufferSubData(gl.ARRAY_BUFFER, 0, this.f32, 0, this.n * 24);
		gl.bindTexture(gl.TEXTURE_2D, this.tex.t);
		gl.drawElements(gl.TRIANGLES, this.n * 6, gl.UNSIGNED_SHORT, 0);
		this.draws++; this.quads += this.n;
		this.n = 0;
	},
	end() { this.flush(); },
	/** 0 the usual blending, 1 adding light */
	blend(mode) {
		if (mode === this.blendMode) return;
		this.flush();
		this.blendMode = mode;
		const gl = this.gl;
		if (mode === 1) gl.blendFunc(gl.SRC_ALPHA, gl.ONE); else gl.blendFunc(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA);
	},
	// ---- a small transform stack (for things that turn: vehicles, creatures falling over)
	push() { this.stack.push(this.m.slice()); },
	pop() { this.m = this.stack.pop(); const m = this.m; this.ident = m[0] === 1 && m[1] === 0 && m[2] === 0 && m[3] === 1 && m[4] === 0 && m[5] === 0; },
	translate(x, y) { const m = this.m; m[4] += m[0] * x + m[2] * y; m[5] += m[1] * x + m[3] * y; this.ident = false; },
	rotate(a) { const m = this.m, c = Math.cos(a), s = Math.sin(a); const a0 = m[0], a1 = m[1], a2 = m[2], a3 = m[3]; m[0] = a0 * c + a2 * s; m[1] = a1 * c + a3 * s; m[2] = a2 * c - a0 * s; m[3] = a3 * c - a1 * s; this.ident = false; },
	scale(sx, sy) { const m = this.m; m[0] *= sx; m[1] *= sx; m[2] *= sy; m[3] *= sy; this.ident = false; },

	/** a textured quad from four corners (top left, top right, bottom left, bottom right) */
	quad(tex, x0, y0, x1, y1, x2, y2, x3, y3, u0, v0, u1, v1, c0, c1, c2, c3, add) {
		if (tex !== this.tex || this.n >= this.MAXQ) { this.flush(); this.tex = tex; }
		if (!this.ident) {
			const m = this.m;
			let t;
			t = x0; x0 = m[0] * t + m[2] * y0 + m[4]; y0 = m[1] * t + m[3] * y0 + m[5];
			t = x1; x1 = m[0] * t + m[2] * y1 + m[4]; y1 = m[1] * t + m[3] * y1 + m[5];
			t = x2; x2 = m[0] * t + m[2] * y2 + m[4]; y2 = m[1] * t + m[3] * y2 + m[5];
			t = x3; x3 = m[0] * t + m[2] * y3 + m[4]; y3 = m[1] * t + m[3] * y3 + m[5];
		}
		const f = this.f32, u = this.u32;
		let o = this.n * 24;
		f[o] = x0; f[o + 1] = y0; f[o + 2] = u0; f[o + 3] = v0; u[o + 4] = c0; f[o + 5] = add;
		f[o + 6] = x1; f[o + 7] = y1; f[o + 8] = u1; f[o + 9] = v0; u[o + 10] = c1; f[o + 11] = add;
		f[o + 12] = x2; f[o + 13] = y2; f[o + 14] = u0; f[o + 15] = v1; u[o + 16] = c2; f[o + 17] = add;
		f[o + 18] = x3; f[o + 19] = y3; f[o + 20] = u1; f[o + 21] = v1; u[o + 22] = c3; f[o + 23] = add;
		this.n++;
	},
	/** a picture from any texture: where on screen, which part of the texture (0...1), a tint */
	img(tex, x, y, w, h, u0, v0, u1, v1, col = WHITE, add = 0) {
		this.quad(tex, x, y, x + w, y, x, y + h, x + w, y + h, u0, v0, u1, v1, col, col, col, col, add);
	},
	/** a picture from the atlas: its place there in pixels (flip mirrors it) */
	sprite(ax, ay, aw, ah, x, y, w, h, col = WHITE, flip = false, add = 0) {
		const e = 0.02;
		let u0 = (ax + e) / Atlas.w, u1 = (ax + aw - e) / Atlas.w;
		if (flip) { const t = u0; u0 = u1; u1 = t; }
		this.quad(Atlas.tex, x, y, x + w, y, x, y + h, x + w, y + h, u0, (ay + e) / Atlas.h, u1, (ay + ah - e) / Atlas.h, col, col, col, col, add);
	},
	rect(x, y, w, h, col) { this.quad(Atlas.tex, x, y, x + w, y, x, y + h, x + w, y + h, this.wu, this.wv, this.wu, this.wv, col, col, col, col, 0); },
	/** a rectangle fading from one colour at the top to another at the bottom */
	grad(x, y, w, h, top, bot) { this.quad(Atlas.tex, x, y, x + w, y, x, y + h, x + w, y + h, this.wu, this.wv, this.wu, this.wv, top, top, bot, bot, 0); },
	/** a rectangle fading from one colour on the left to another on the right */
	gradH(x, y, w, h, lf, rt) { this.quad(Atlas.tex, x, y, x + w, y, x, y + h, x + w, y + h, this.wu, this.wv, this.wu, this.wv, lf, rt, lf, rt, 0); },
	oval(x, y, w, h, col) { this.quad(Atlas.tex, x, y, x + w, y, x, y + h, x + w, y + h, this.cu0, this.cv0, this.cu1, this.cv1, col, col, col, col, 0); },
	line(x0, y0, x1, y1, width, col) {
		const dx = x1 - x0, dy = y1 - y0, len = Math.hypot(dx, dy);
		if (len < 0.0001) return;
		const nx = -dy / len * width * 0.5, ny = dx / len * width * 0.5;
		this.quad(Atlas.tex, x0 + nx, y0 + ny, x1 + nx, y1 + ny, x0 - nx, y0 - ny, x1 - nx, y1 - ny, this.wu, this.wv, this.wu, this.wv, col, col, col, col, 0);
	},
	/** the outline of a rectangle */
	frame(x, y, w, h, t, col) { this.rect(x, y, w, t, col); this.rect(x, y + h - t, w, t, col); this.rect(x, y + t, t, h - 2 * t, col); this.rect(x + w - t, y + t, t, h - 2 * t, col); },
};

/** Loads the atlas picture, keeps its pixels (the painter and the icons read them) and adds the shapes */
function loadAtlas() {
	return new Promise((resolve, reject) => {
		const im = new Image();
		im.onload = () => {
			const c = document.createElement("canvas");
			c.width = Atlas.w; c.height = Atlas.h;
			const g = c.getContext("2d", { willReadFrequently: true });
			g.drawImage(im, 0, 0);
			const id = g.getImageData(0, 0, Atlas.w, Atlas.h);
			Atlas.px = new Uint8Array(id.data.buffer);
			Atlas.px32 = new Uint32Array(id.data.buffer);
			// a white square and a round dot in the room kept free at the bottom of the sheet
			const fy = DATA.atlas.freeY + 2, p = Atlas.px32, W = Atlas.w;
			for (let y = 0; y < 6; y++) for (let x = 0; x < 6; x++) p[(fy + y) * W + 2 + x] = 0xFFFFFFFF;
			const D = 64, cx0 = 16;
			for (let y = 0; y < D; y++) for (let x = 0; x < D; x++) {
				const dx = (x + 0.5 - D / 2) / (D / 2), dy = (y + 0.5 - D / 2) / (D / 2);
				p[(fy + y) * W + cx0 + x] = dx * dx + dy * dy <= 1 ? 0xFFFFFFFF : 0x00FFFFFF;
			}
			R.wu = 5 / W; R.wv = (fy + 3) / Atlas.h;
			R.cu0 = cx0 / W; R.cv0 = fy / Atlas.h; R.cu1 = (cx0 + D) / W; R.cv1 = (fy + D) / Atlas.h;
			Atlas.orig = Atlas.px.slice();
			Atlas.tex = R.makeTex(Atlas.w, Atlas.h, Atlas.px, false);
			resolve();
		};
		im.onerror = () => reject(new Error("the art could not be read"));
		im.src = ATLAS_PNG;
	});
}
/** where a named sprite frame is in the atlas: [x, y, w, h] */
function spriteRect(name, frame = 0) { const r = DATA.atlas.rects[name]; return r ? r[Math.min(frame, r.length - 1)] : null; }
/** where a tile's picture is in the atlas */
const tileAX = (t) => (t % 64) * 16;
const tileAY = (t) => Math.floor(t / 64) * 16;
