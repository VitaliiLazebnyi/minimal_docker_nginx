# Contributing to minimal_docker_nginx

Bug reports and pull requests are welcome on GitHub at <https://github.com/VitaliiLazebnyi/minimal_docker_nginx>.
Behavioral defects are tracked in [BUGS.md](BUGS.md) against the requirement they break
([REQUIREMENTS.md](REQUIREMENTS.md)).

## Getting Started

The Rails application lives in `rails_app/` and develops on the Ruby in `rails_app/.ruby-version`.

```bash
cd rails_app && bundle install && cd ..
# actionlint, gixy, rumdl, ShellCheck, typos, yamllint, zizmor:
python3 -m pip install --require-hashes -r tools/requirements.txt
# shfmt and editorconfig-checker (Linux x86-64; elsewhere, the release of tools/binaries.json):
TOOLS_DIR="$HOME/.local/bin" script/install_binaries.sh
git config core.hooksPath .githooks   # optional: run the fast checks before every commit
```

## Before Opening a Pull Request

```bash
script/check                  # every check, in order
script/check rubocop yamllint # or only the named ones
```

`script/check` is what every CI job runs (each step names its checks), so a local run checks exactly what CI checks.
Every check fails the build:

- Ruby (`rails_app/`, and the Ruby scripts of `script/`), through the tasks of `rails_app/Rakefile`:
  - `spec`: RSpec; 100% line, branch **and** method coverage (SimpleCov) of every file of the application, of the
    helpers of the Rakefile (`rails_app/lib/tasks/quality_gates.rb`) and of the scripts of `script/` (each script is
    specified in `rails_app/spec/script/`, against canned HTTPS responses and temporary repositories), no pending or
    skipped example, no Ruby warning from the application, the scripts or the specs, Rails deprecations raise.
  - `rubocop`: every cop of RuboCop and of its plugins (`rubocop-rails`, `rubocop-rspec`, `rubocop-rspec_rails`,
    `rubocop-performance`, `rubocop-rake`, `rubocop-sorbet`, `rubocop-thread_safety`, `rubocop-yard`, `rubocop-md`,
    `rubocop-ai`); `rails_app/.rubocop.yml` lists the few cops that cannot apply, with the reason; no todo file.
  - `typecheck`: Tapioca generates the gem and DSL RBIs, then `srb tc` must report no errors. The application, the
    scripts and most of the configuration are `typed: strong`, the specs and the Rails environment files
    `typed: strict` (with Sorbet's RSpec support); only `config.ru` and `config/puma.rb`, which Rack and Puma
    evaluate with `instance_eval`, are `typed: false`.
  - `yard`: 100% documented, private and protected objects included, without a YARD warning (`yardoc
    --fail-on-warning`; application and scripts).
  - `reek`, `flay`, `flog`, `debride`: no code smell, no structural duplication, no method with a Flog score above 20,
    no method without a caller.
  - `brakeman`, `audit`: Brakeman (every check, no ignore file) and bundler-audit.
  - `outdated`: every dependency at its newest release, except the documented holds of `script/outdated_holds.yml`:
    the gems, Bundler and RubyGems, every pinned Ruby, the nginx release the image builds, the Docker images of the
    Dockerfile and of `tools/images.json` (newest tag, and the digest the tag points to), every GitHub Action (newest
    release, pinned to its commit), the Python tools and the release binaries of `tools/binaries.json`.
  - `mutant`: mutation testing of the application, of the Rakefile helpers and of the scripts; every mutation must be
    killed, with no ignore pattern (`rails_app/.mutant.yml`). Mutant parses the code with the `parser` gem, which
    only has a grammar for Ruby 3.3: CI runs it on the newest Ruby 3.3.
  - `scorecards` (Dependency review job only): the OpenSSF Scorecard gate of the dependencies a pull request adds.
- The repository: `suppressions` (see below), `actionlint` (with ShellCheck on every `run:` block), `zizmor`
  (auditor persona, its strictest; online audits when `GH_TOKEN` is set), `shellcheck` (every optional check, every
  severity), `shfmt` (`.editorconfig`), `typos`, `rumdl` (every rule, each style fixed, `.rumdl.toml`), `lychee`
  (every link of every Markdown file, external ones and anchors included, no redirect; `lychee.toml`), `yamllint`
  (every rule, strict, `.yamllint.yml`) and `editorconfig` (editorconfig-checker).
- Code: `semgrep` (the rule packs of Ruby and Rails, shell, Dockerfile, nginx, GitHub Actions and secrets, and the
  cross-language security packs; every tracked file, `test/` included, see `.semgrepignore`).
- Docker: `hadolint` (every severity, OCI labels, trusted registries; `.hadolint.yaml`), `buildkit` (BuildKit's build
  checks), `trivy_config` (Trivy's misconfiguration rules), `gitleaks` (the whole history), `trivy_fs` (every lockfile
  and the working tree) and `image`: the build, container-structure-test (`test/image/structure-tests.yaml`, which
  runs `nginx -t` inside the image), the end-to-end smoke test (`test/image/smoke_test.sh`), Dockle (every level),
  Trivy and Grype (any fixable vulnerability) and gixy on the rendered `nginx.conf`.

Ruby warnings are on (`RUBYOPT=-w -W:deprecated -W:performance`) for every command, the development tools included.
`script/check` fails a check whose output contains a warning or a deprecation notice (`script/warnings.sh`), exactly
as the warning gate of every workflow does; the only warnings that do not count are the few verbose-mode warnings that
third-party gems print about their own code, each listed with its gem release, file, line and message in
`script/upstream_warnings.txt`.

In CI, every job also runs behind `step-security/harden-runner` with an egress allow-list (`egress-policy: block`, no
`sudo`, and no containers in the jobs that need none), the dependency review fails on vulnerabilities of any severity,
and CodeQL scans the Ruby code and the workflows with the security-extended and security-and-quality suites.

## Rules

- **No inline suppressions.** Nothing may silence a linter, scanner, type checker, warning or test in place: no
  `rubocop:disable`, `:nocov:`, `:reek:`, `mutant:disable`, `hadolint ignore`, `shellcheck disable`,
  `rumdl-disable`/`markdownlint-disable`, `yamllint disable`, `editorconfig-checker-disable`, `gitleaks:allow`, `nosec`,
  `nosemgrep`, `T.unsafe`/`T.cast`/`T.bind`/`T.untyped` in any Ruby file, `$VERBOSE = nil`, `skip`/`pending`/`focus`,
  and so on, and no suppression or todo file (`.rubocop_todo.yml`, `.trivyignore`, `.grype.yaml`, `.dockleignore`,
  `brakeman.ignore`, `sorbet/rbi/todo.rbi`, `.lycheeignore`, an `exclude` of `lychee.toml`, a path in
  `.semgrepignore`, ...). Fix the cause. A rule that cannot apply is configured narrowly in the tool's configuration
  file, with the reason written next to it (`.hadolint.yaml`, `rails_app/.rubocop.yml`, `.rumdl.toml`, `.yamllint.yml`,
  `.editorconfig-checker.json`, `_typos.toml`).
- **No warnings.** Every workflow ends with a "Warning gate (workflow)" job (`script/warning_gate.sh`) that fails the
  run when the log of any job contains a warning or a deprecation notice (`script/warnings.sh`, as `script/check`
  does). The output of compiling Ruby, nginx and Passenger inside the image build (third-party C code) is kept in the
  `build.log` of the `image-reports` artifact rather than in the job log; the Dockerfile itself is held to zero
  findings by hadolint and BuildKit's build checks.
- **Behavior is specified.** Every behavioral fix needs a regression test (a spec, a structure test or a smoke-test
  step), and every surviving mutant needs a test that kills it (or, when the mutation cannot change observable
  behavior, simpler code).
- **Dependencies come from well-maintained projects.** On every pull request, `script/scorecards.rb` (Dependency
  review job) fails when an added dependency has an [OpenSSF Scorecard](https://scorecard.dev) below 3, unless
  `script/scorecard_allowances.yml` allows that one package with the reason it cannot be dropped. Drop or replace a
  low-scoring dependency first (Markdown is linted with rumdl, a single binary, instead of markdownlint-cli2 and its
  low-scoring npm dependencies; the Rails app depends on the frameworks it loads, not on the `rails` meta-gem).
- **Everything is pinned and current.** Docker images are pinned by digest, GitHub Actions by commit, Python tools by
  hash, release binaries by SHA-256; `rake outdated` keeps them at their newest releases.
