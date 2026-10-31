#!/bin/bash
# Claude Code cloud sessions: install the Swift toolchain and the SwiftUI/AVFoundation stand-ins the
# headless tests build against (see tools/setup.sh). Runs before the session starts; quick when the
# container already has them.
set -euo pipefail
if [ "${CLAUDE_CODE_REMOTE:-}" != "true" ]; then
    exit 0
fi
"${CLAUDE_PROJECT_DIR:-$(cd "$(dirname "$0")/../.." && pwd)}/tools/setup.sh"
