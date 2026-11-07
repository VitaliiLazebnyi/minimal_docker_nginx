#!/usr/bin/env bash
# OpenSSF Scorecard reports its findings about the whole repository (Branch-Protection, Code-Review, Fuzzing, ...)
# under the placeholder URI "no file associated with this alert", which code scanning's SARIF upload rejects with a
# warning. Points them at the Scorecard workflow, the file that produces them.
# Usage: script/locate_scorecard_findings.sh SARIF_FILE   (rewritten in place)
set -euo pipefail

sarif=${1:?usage: script/locate_scorecard_findings.sh SARIF_FILE}
filter='(.runs[].results[]?.locations[]?.physicalLocation.artifactLocation
  | select(.uri == "no file associated with this alert")).uri = ".github/workflows/scorecard.yml"'
located=$(jq "${filter}" "${sarif}")
printf '%s\n' "${located}" >"${sarif}"
