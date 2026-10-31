# Paths shared by the tools scripts (sourced, not run).
# tools/setup.sh installs the toolchain and stand-ins under PR_HOME; builds go to PR_BUILD.
PR_HOME="${PR_HOME:-/opt/pixelrealm}"
PR_SWIFT="$PR_HOME/swift"
PR_SHIM="$PR_HOME/shim"
PR_BUILD="${PR_BUILD:-/tmp/pixelrealm-build}"
PR_TOOLS="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PR_REPO="$(cd "$PR_TOOLS/.." && pwd)"
PR_GAME="${GAME_SRC:-$PR_REPO/PixelRealm.swift}"
PR_BIN="$PR_SWIFT/usr/libexec/swift/bin"
# the toolchain's own libraries, set only for the commands that need them (never session-wide)
PR_LIBS="$PR_SWIFT/usr/lib/x86_64-linux-gnu:$PR_SWIFT/usr/libexec/swift/lib:$PR_SWIFT/usr/libexec/swift/lib/swift/linux"

pr_need_toolchain() {
    if [ ! -x "$PR_BIN/swiftc" ] || [ ! -f "$PR_SHIM/libSwiftUI.a" ]; then
        echo "Swift toolchain or stand-ins missing: run tools/setup.sh first" >&2
        exit 1
    fi
}
