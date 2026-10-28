#!/usr/bin/env bash
# Fails when a tracked file silences a linter, scanner, type checker, warning or test, or weakens typing,
# and when a suppression or todo file of one of the tools exists.
# Inline suppressions are forbidden everywhere in this repository (see CONTRIBUTING.md): fix the cause.
# Markdown files are skipped because they document the rules.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

# This script names the patterns, so it is not scanned for them. Committed central-repository RBI
# annotations (sorbet/rbi/annotations) are third-party type information, not code of this repository.
files=$(git ls-files -z -- . ':(exclude)*.md' ':(exclude)script/forbidden_suppressions.sh' \
  ':(exclude)rails_app/sorbet/rbi/annotations' | tr '\0' '\n')

status=0
check() {
  local description=$1 pattern=$2 scope=${3:-.}
  local hits
  hits=$(printf '%s\n' "${files}" | grep -E "^${scope}" | xargs -r grep -nEH -e "${pattern}" -- || true)
  if [[ -n "${hits}" ]]; then
    printf 'Forbidden (%s):\n%s\n\n' "${description}" "${hits}"
    status=1
  fi
}

check 'RuboCop directive' 'rubocop:(disable|enable|todo)'
check 'Reek suppression' ':reek:'
check 'SimpleCov exclusion' ':nocov:|nocov_token|SimpleCov\.nocov'
check 'mutant suppression' 'mutant:disable'
check 'gitleaks allow' 'gitleaks:allow'
check 'zizmor ignore' 'zizmor: ?ignore'
check 'shellcheck disable' 'shellcheck +disable'
check 'hadolint ignore' 'hadolint +ignore'
check 'Trivy ignore' 'trivy: ?ignore'
check 'markdownlint suppression' 'markdownlint-(disable|capture|configure-file)'
check 'typos suppression' 'typos: ?(ignore|off)|spellchecker: ?disable'
check 'Brakeman ignore' 'brakeman:? ?ignore'
check 'LGTM/CodeQL suppression' 'lgtm\[|codeql\[|codeql-disable|lgtm: ?ignore'
check 'nosec' 'nosec|NOLINT'
check 'warning silencing' '[$]VERBOSE *= *(nil|false)|Warning\.ignore|silence_warnings|[$]stderr *= *File::NULL|Warning\[:[a-z]+\] *= *false|-W0|--no-warnings'
check 'deprecation silencing' 'ActiveSupport::Deprecation\.(silence|behavior *= *:silence)|deprecation *= *:(silence|log|notify)|report_deprecations *= *false' 'rails_app/(app|lib|spec|config/environments/test\.rb)'
check 'skipped or focused test' '^[[:space:]]*(xit|xspecify|xexample|xdescribe|xcontext|fit|fspecify|fexample|fdescribe|fcontext|skip|pending)([[:space:]]|\()|focus: *true|, *:focus|, *(skip|pending): ' 'rails_app/spec/'
check 'Sorbet escape hatch' 'T\.(unsafe|cast|bind|untyped)\b|typed: *(false|ignore|true)\b' 'rails_app/(app|lib)/'

# Suppression and todo files of the tools: findings are fixed, never parked in a file.
for forbidden in .rubocop_todo.yml rails_app/.rubocop_todo.yml rails_app/sorbet/rbi/todo.rbi \
  .trivyignore .trivyignore.yaml .grype.yaml .dockleignore rails_app/config/brakeman.ignore \
  .gitleaksignore .markdownlintignore .typos-ignore; do
  if [[ -e "${forbidden}" ]]; then
    printf 'Forbidden (suppression or todo file): %s\n\n' "${forbidden}"
    status=1
  fi
done

exit "${status}"
