#!/bin/bash
# Installs what the headless tests need, outside the repo, and skips whatever is already done:
#   - Swift 6.0.3: Ubuntu's swiftlang packages, unpacked into $PR_HOME/swift (no system install;
#     swift.org downloads are blocked in cloud sessions, Ubuntu's archive is not)
#   - libxml2.so.16 for sourcekit-lsp (the compiler doesn't need it; Ubuntu 24.04 only has .so.2)
#   - small wrappers in $PR_HOME/bin (swiftc, swift-frontend, swift-format, sourcekit-lsp) that set
#     the toolchain's library path for themselves, and sourcekit-lsp linked into /usr/local/bin so
#     the swift-lsp plugin finds it
#   - the SwiftUI and AVFoundation stand-ins from tools/shim, rebuilt whenever their source changes
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/env.sh"

VER="6.0.3-2build1"
SHA_swiftlang="b233b51932e8bda24e4d17c9cc5585b2309ef062278ffc56caae1f76f1225233"
SHA_libswiftlang="215d409dd0852b6dda1a0391aeb229130107c3ac2dfd133ce28dd823308bb76f"
XML_DEB="libxml2-16_2.14.5+dfsg-0.2ubuntu0.2_amd64.deb"
SHA_XML="597eea8a0abcdceb34497a75664c8d37622f72a5660af1db47ab3a056a0e60cc"
MIRRORS="http://archive.ubuntu.com/ubuntu http://security.ubuntu.com/ubuntu"

# downloads a .deb from the Ubuntu archive and checks it: fetch <pool path> <file> <sha256>
fetch() {
    for mirror in $MIRRORS; do
        for attempt in 1 2 3; do
            if curl -fsSL -o "$2" "$mirror/pool/$1" && echo "$3  $2" | sha256sum -c --quiet -; then return 0; fi
            sleep $((attempt * 2))
        done
    done
    echo "Could not download $1 (or its checksum did not match)" >&2
    return 1
}

mkdir -p "$PR_HOME"

if [ ! -x "$PR_BIN/swiftc" ]; then
    echo "Installing Swift $VER into $PR_SWIFT ..."
    tmp="$(mktemp -d)"
    trap 'rm -rf "$tmp"' EXIT
    for pkg in swiftlang libswiftlang; do
        want="SHA_${pkg}"
        fetch "universe/s/swiftlang/${pkg}_${VER}_amd64.deb" "$tmp/${pkg}_${VER}_amd64.deb" "${!want}"
    done
    # unpack beside the target and move it into place, so an interrupted run never looks finished
    rm -rf "$PR_SWIFT.partial"
    mkdir -p "$PR_SWIFT.partial"
    for pkg in swiftlang libswiftlang; do dpkg -x "$tmp/${pkg}_${VER}_amd64.deb" "$PR_SWIFT.partial"; done
    rm -rf "$PR_SWIFT"
    mv "$PR_SWIFT.partial" "$PR_SWIFT"
    rm -rf "$tmp"
    trap - EXIT
fi

extra="$PR_SWIFT/usr/lib/x86_64-linux-gnu"
if [ ! -e "$extra/libxml2.so.16" ]; then
    echo "Adding libxml2.so.16 for sourcekit-lsp ..."
    tmpx="$(mktemp -d)"
    fetch "main/libx/libxml2/$XML_DEB" "$tmpx/libxml2.deb" "$SHA_XML"
    dpkg -x "$tmpx/libxml2.deb" "$tmpx/x"
    mkdir -p "$extra"
    cp -a "$tmpx"/x/usr/lib/x86_64-linux-gnu/libxml2.so.16* "$extra/"
    rm -rf "$tmpx"
fi

mkdir -p "$PR_HOME/bin"
for tool in swiftc swift-frontend swift-format sourcekit-lsp; do
    cat > "$PR_HOME/bin/$tool" <<EOF
#!/bin/bash
export LD_LIBRARY_PATH="$PR_LIBS\${LD_LIBRARY_PATH:+:\$LD_LIBRARY_PATH}"
exec "$PR_BIN/$tool" "\$@"
EOF
    chmod +x "$PR_HOME/bin/$tool"
done
# the swift-lsp plugin starts "sourcekit-lsp" by name, outside the shell's PATH
if [ -w /usr/local/bin ]; then ln -sf "$PR_HOME/bin/sourcekit-lsp" /usr/local/bin/sourcekit-lsp; fi

stamp="$(cat "$PR_TOOLS"/shim/*.swift | sha256sum | cut -d' ' -f1)"
if [ "$(cat "$PR_SHIM/.stamp" 2>/dev/null || true)" != "$stamp" ]; then
    echo "Building the SwiftUI and AVFoundation stand-ins into $PR_SHIM ..."
    mkdir -p "$PR_SHIM" "$PR_HOME/shimbuild"
    for mod in SwiftUI AVFoundation; do
        (cd "$PR_HOME/shimbuild" && "$PR_HOME/bin/swiftc" -O -parse-as-library -emit-module \
            -emit-module-path "$PR_SHIM/$mod.swiftmodule" -module-name "$mod" -emit-library -static \
            -o "$PR_SHIM/lib$mod.a" "$PR_TOOLS/shim/$mod.swift")
    done
    echo "$stamp" > "$PR_SHIM/.stamp"
fi

# later commands in a Claude Code session find the wrappers on PATH
if [ -n "${CLAUDE_ENV_FILE:-}" ]; then
    echo "export PATH=\"$PR_HOME/bin:\$PATH\"" >> "$CLAUDE_ENV_FILE"
fi
echo "Ready: $("$PR_HOME/bin/swiftc" --version 2>&1 | head -1)"
