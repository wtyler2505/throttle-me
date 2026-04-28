#!/bin/bash
# PreToolUse hook: block edits to throttle-me.original.
# Reads Claude Code hook JSON from stdin; exits 0 (allow) or 2 (block).

set -euo pipefail

input="$(cat)"

if ! command -v jq >/dev/null 2>&1; then
    exit 0
fi

file_path="$(printf '%s' "${input}" | jq -r '.tool_input.file_path // empty' 2>/dev/null || true)"

[[ -z "${file_path}" ]] && exit 0

case "${file_path}" in
    */throttle-me.original|throttle-me.original)
        cat >&2 <<'EOF'
BLOCKED: throttle-me.original is the v1 reference snapshot — do not modify.
All work goes in `throttle-me` + `lib/*.sh`.
See CLAUDE.md rule #7.
EOF
        exit 2
        ;;
    *)
        exit 0
        ;;
esac
