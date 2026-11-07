#!/usr/bin/env bash
# Prints the active Ruby and fails unless it is exactly the expected version.
# Usage: script/check_ruby.sh [expected-version]   (defaults to the contents of rails_app/.ruby-version)
set -euo pipefail

version_file="$(dirname "$0")/../rails_app/.ruby-version"
expected="${1:-$(tr -d '[:space:]' < "${version_file}")}"
ruby -v
actual="$(ruby -e 'print RUBY_VERSION')"
if [[ "${actual}" != "${expected}" ]]; then
  echo "Expected Ruby ${expected} but running ${actual}" >&2
  exit 1
fi
