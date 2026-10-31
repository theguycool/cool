#!/bin/bash
# Builds and runs the headless test suites, a few at a time.
#   tools/run-tests.sh              every suite
#   tools/run-tests.sh power combat just those (folder names under tools/tests)
#   JOBS=2 tools/run-tests.sh       fewer at once (each build takes about 1.5 GB)
# A line per suite: how many checks failed and its last line. Full output: $PR_BUILD/<suite>/out.log
# Exits non-zero if any suite fails to build or has a FAIL line.
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/env.sh"
pr_need_toolchain
export PR_FIXTURES="$PR_TOOLS/fixtures"
suites=("$@")
if [ ${#suites[@]} -eq 0 ]; then
    for d in "$PR_TOOLS"/tests/*/; do suites+=("$(basename "$d")"); done
fi
run_one() {
    s="$1"
    dir="$PR_BUILD/$s"
    rm -rf "$dir"
    mkdir -p "$dir"
    if ! "$PR_TOOLS/build.sh" "$PR_TOOLS/tests/$s/main.swift" "$dir/t.bin" > "$dir/build.log" 2>&1; then
        echo "$s: BUILD FAILED $(head -3 "$dir/build.log")"
        return 1
    fi
    (cd "$dir" && LD_LIBRARY_PATH="$PR_LIBS" timeout 1500 ./t.bin > out.log 2>&1)
    code=$?
    fails=$(grep -c '^FAIL' "$dir/out.log")
    echo "$s: exit $code :: $fails FAIL :: $(tail -1 "$dir/out.log")"
    grep '^FAIL' "$dir/out.log" | head -10
    [ "$code" -eq 0 ] && [ "$fails" -eq 0 ]
}
export -f run_one
export PR_BUILD PR_TOOLS PR_LIBS
printf '%s\n' "${suites[@]}" | xargs -P "${JOBS:-4}" -I{} bash -c 'run_one "$@"' _ {}
