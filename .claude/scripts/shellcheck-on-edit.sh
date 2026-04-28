#!/bin/bash
# PostToolUse hook: run shellcheck on edited shell files.
# Reads Claude Code hook JSON from stdin; exits 0 (silent) or 2 (warn).

set -euo pipefail

input="$(cat)"

if ! command -v jq >/dev/null 2>&1; then
    echo "shellcheck-on-edit: jq not installed; cannot parse hook input" >&2
    exit 0
fi

file_path="$(printf '%s' "${input}" | jq -r '.tool_input.file_path // empty' 2>/dev/null || true)"

[[ -z "${file_path}" ]] && exit 0
[[ ! -f "${file_path}" ]] && exit 0

# Match shell files: anything ending in .sh, or the two extensionless main scripts.
case "${file_path}" in
    *.sh|*/throttle-me|*/throttle-me-daemon)
        ;;
    *)
        exit 0
        ;;
esac

if ! command -v shellcheck >/dev/null 2>&1; then
    echo "shellcheck-on-edit: shellcheck not installed; install with 'apt install shellcheck'" >&2
    exit 0
fi

# Filter: --severity=warning drops style/info noise (matches CLAUDE.md "style is noise").
# --exclude=SC2154 silences the false-positive on ${CONFIG[...]} from sourced lib/config.sh
# (the project's .shellcheckrc disables SC1090/SC1091 so cross-file refs look unassigned).
if ! output="$(shellcheck --severity=warning --exclude=SC2154 "${file_path}" 2>&1)"; then
    {
        echo "shellcheck flagged issues in ${file_path}:"
        echo "${output}"
    } >&2
    exit 2
fi

exit 0
