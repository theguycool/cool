#!/bin/bash
# Typechecks the game against the stand-ins (about 25 s): the quick check after every edit.
# Prints only errors; exits non-zero if there are any.
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/env.sh"
pr_need_toolchain
out="$(LD_LIBRARY_PATH="$PR_LIBS" "$PR_BIN/swift-frontend" -typecheck -I "$PR_SHIM" -parse-as-library "$PR_GAME" 2>&1)"
status=$?
echo "$out" | grep -E "error" | head -40
if [ $status -ne 0 ]; then exit 1; fi
echo "typecheck OK"
