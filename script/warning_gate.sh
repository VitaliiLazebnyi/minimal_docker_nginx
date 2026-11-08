#!/usr/bin/env bash
# Fails when the log of any other job of the current workflow run contains a warning or a deprecation notice
# (script/warnings.sh). Run by the "Warning gate (workflow)" job of every workflow: the repository tolerates no warnings
# (CONTRIBUTING.md).
#
# Needs GH_TOKEN (actions: read), GITHUB_REPOSITORY, GITHUB_RUN_ID and GATE_JOB_NAME (the name of the gate job itself,
# whose own log quotes the warnings it finds).
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
repository=${GITHUB_REPOSITORY:?}
run_id=${GITHUB_RUN_ID:?}
gate_job_name=${GATE_JOB_NAME:?}
token=${GH_TOKEN:?}

jobs=$(gh api --paginate "repos/${repository}/actions/runs/${run_id}/jobs?per_page=100" \
  --jq ".jobs[] | select(.name != \"${gate_job_name}\" and .conclusion != \"skipped\") | \"\(.id)\t\(.name)\"")

status=0
while IFS=$'\t' read -r id name; do
  [[ -n ${id} ]] || continue
  # Downloaded with curl: depending on its version, gh refuses to print a log that contains terminal escape
  # sequences (colored tool output), and older versions do not know the flag that allows them.
  log=$(curl --fail --silent --show-error --location \
    --header "Authorization: Bearer ${token}" --header 'Accept: application/vnd.github+json' \
    "${GITHUB_API_URL:-https://api.github.com}/repos/${repository}/actions/jobs/${id}/logs")
  if hits=$(printf '%s\n' "${log}" | "${root}/script/warnings.sh"); then
    printf 'No warnings in the log of job "%s"\n' "${name}"
  else
    printf '::error::Warnings in the log of job "%s"\n%s\n\n' "${name}" "${hits}"
    status=1
  fi
done <<<"${jobs}"

exit "${status}"
