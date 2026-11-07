#!/usr/bin/env bash
# Installs the standalone linters of tools/binaries.json (Linux x86-64) into TOOLS_DIR (default
# ${RUNNER_TEMP}/tools) and, in GitHub Actions, adds that directory to the PATH of the later steps. Every download
# is verified against its pinned SHA-256 before it is unpacked.
# Usage: script/install_binaries.sh   (every tool of tools/binaries.json)
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
pins="${root}/tools/binaries.json"
tools_dir="${TOOLS_DIR:-${RUNNER_TEMP:?RUNNER_TEMP or TOOLS_DIR is required}/tools}"
mkdir -p "${tools_dir}"

# A field of a tool of tools/binaries.json ("" when the tool has none).
field() {
  jq --raw-output --arg tool "$1" --arg key "$2" '.[$tool][$key] // ""' "${pins}"
}

install_tool() {
  local tool=$1 repository version asset sha256 member file unpacked
  repository=$(field "${tool}" repository)
  version=$(field "${tool}" version)
  asset=$(field "${tool}" asset)
  sha256=$(field "${tool}" sha256)
  member=$(field "${tool}" member)
  asset=${asset//\{version\}/${version}}
  file="${tools_dir}/${asset}"

  curl --fail --silent --show-error --location --output "${file}" \
    "https://github.com/${repository}/releases/download/v${version}/${asset}"
  echo "${sha256}  ${file}" | sha256sum --check --strict --quiet

  if [[ -z ${member} ]]; then
    install -m 0755 "${file}" "${tools_dir}/${tool}"
  else
    unpacked="${tools_dir}/${tool}.unpacked"
    mkdir -p "${unpacked}"
    tar -xf "${file}" -C "${unpacked}" "${member}"
    install -m 0755 "${unpacked}/${member}" "${tools_dir}/${tool}"
    rm -rf "${unpacked}"
  fi
  rm -f "${file}"
  echo "Installed ${tool} ${version}"
}

tools=$(jq --raw-output 'keys[] | select(startswith("$") | not)' "${pins}")
for tool in ${tools}; do
  install_tool "${tool}"
done

if [[ -n ${GITHUB_PATH:-} ]]; then
  echo "${tools_dir}" >>"${GITHUB_PATH}"
fi
