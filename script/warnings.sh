#!/usr/bin/env bash
# Reads a log on standard input and fails when it contains a warning or a deprecation notice, printing each such
# line with its line number. The only lines that do not count are the warnings of third-party gems listed in
# script/upstream_warnings.txt (each matched by the gem release, file, line and message).
# Used by script/check (the output of every check) and script/warning_gate.sh (the log of every CI job).
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly root

# Ruby and compiler style "warning:", the log levels of tools (WARN, level=warn, [warn] of nginx), GitHub annotations
# and the deprecation notices of any tool.
pattern='[Ww]arning:|WARNING|(^|[^[:alnum:]_])WARN([^[:alnum:]_]|$)|level=warn|\[warn\]|##\[warning\]|DEPRECATION'
pattern+='|DEPRECATED|is deprecated|will be deprecated|deprecated and will|Node\.js [0-9]+ actions are deprecated'
readonly pattern

upstream=$(grep -vE '^(#|$)' "${root}/script/upstream_warnings.txt")
readonly upstream

hits=$(grep -nE -e "${pattern}" | grep -vE -e "${upstream}" || true)
if [[ -n ${hits} ]]; then
  printf '%s\n' "${hits}"
  exit 1
fi
