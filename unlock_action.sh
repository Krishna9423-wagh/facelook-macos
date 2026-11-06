#!/usr/bin/env bash
set -euo pipefail

# MacID-Vision: Local Unlock & Authorization Helper
# Invoked when biometric face verification succeeds upon screen wake.

SIMILARITY="${1:-unknown}"
USERNAME="${2:-$USER}"

TIMESTAMP="$(date '+%Y-%m-%d %H:%M:%S')"

echo "=================================================="
echo "🔓 [MacID-Vision] Authorization Passed!"
echo "   User:       ${USERNAME}"
echo "   Similarity: ${SIMILARITY}"
echo "   Timestamp:  ${TIMESTAMP}"
echo "=================================================="

# 1. Dismiss lock screen / screensaver prompt by pressing Enter
osascript -e 'tell application "System Events" to key code 36' 2>/dev/null || true

# 2. Display desktop confirmation notification
osascript -e "display notification \"Identity verified (${SIMILARITY})\" with title \"MacID Vision\" subtitle \"Lock State Dismissed\"" 2>/dev/null || true

exit 0

