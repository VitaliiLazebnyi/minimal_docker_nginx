# Contributing to minimal_docker_nginx

Bug reports and pull requests are welcome on GitHub at <https://github.com/VitaliiLazebnyi/minimal_docker_nginx>.
Behavioral defects are tracked in [BUGS.md](BUGS.md) against the requirement they break
([REQUIREMENTS.md](REQUIREMENTS.md)).

## Getting started

The Rails application lives in `rails_app/` and develops on the Ruby in `rails_app/.ruby-version`.

```bash
cd rails_app && bundle install && cd ..
python3 -m pip install --require-hashes -r tools/requirements.txt   # actionlint, gixy, ShellCheck, typos, zizmor
npm ci                                                             # markdownlint-cli2
git config core.hooksPath .githooks   # optional: run the fast gates before every commit
```

## Before opening a pull request

Every gate below is enforced in CI and fails the build.

### Rails application (`rails_app/`)

```bash
cd rails_app
bundle exec rake
```

That runs, in order:

| Task | Gate |
| --- | --- |
| `rake spec` | RSpec; 100% line **and** branch coverage (SimpleCov), no pending or skipped example, no Ruby warning from the application or the specs, Rails deprecations raise |
| `rake rubocop` | RuboCop with the rails, rspec, rspec_rails, performance, rake, sorbet, thread_safety and md plugins (`.rubocop.yml`), on the application and on `script/`; no todo file |
| `rake suppressions` | no inline suppression anywhere (`script/forbidden_suppressions.sh`, see below) |
| `rake typecheck` | Tapioca generates the gem and DSL RBIs, then `srb tc` must report no errors; `app/` and `script/` are `typed: strict` |
| `rake yard` | YARD must report 100% documented (application and scripts) |
| `rake reek flay` | no code smell (default Reek configuration) and no structural duplication |
| `rake brakeman` | Brakeman, every check, no ignore file, zero warnings |
| `rake audit` | bundler-audit: no gem with a known vulnerability |

Not part of the default task, but also enforced in CI:

```bash
bundle exec rake mutant     # mutation testing; every mutation must be killed (.mutant.yml)
bundle exec rake outdated   # every dependency at its newest release, except the documented holds
```

Mutant parses the code with the `parser` gem, which only has a grammar for Ruby 3.3: run it on the newest Ruby 3.3
(CI does) to avoid the `parser/current` warning.

`rake outdated` (`script/outdated.rb`) checks the gems, Bundler and RubyGems, every pinned Ruby, the nginx release the
image builds, every Docker image (newest tag, and the digest the tag points to), every GitHub Action (newest release, pinned
to its commit), and the Python and npm tools. A dependency that cannot be updated is listed, with the reason, in
`script/outdated_holds.yml`; the check also fails when a hold is no longer needed.

### Docker image

```bash
docker run --rm -i hadolint/hadolint:v2.15.1 hadolint - < Dockerfile
docker buildx build --check .
docker build --tag minimal-docker-nginx:ci .
docker run --rm -v /var/run/docker.sock:/var/run/docker.sock -v "$PWD/test/image:/tests:ro" \
  ghcr.io/googlecontainertools/container-structure-test:1.22.1 \
  test --image minimal-docker-nginx:ci --config /tests/structure-tests.yaml
test/image/smoke_test.sh minimal-docker-nginx:ci
```

CI also runs Dockle (every level), Trivy and Grype on the built image (both fail on any vulnerability that has a fix),
and gixy on the rendered `nginx.conf`; the exact commands and pinned images are in `.github/workflows/docker.yml`. The
structure tests run `nginx -t` inside the image.

### Repository

```bash
actionlint
zizmor --persona pedantic .github/workflows
shellcheck script/*.sh test/image/*.sh docker_config/entrypoint.sh .githooks/pre-commit
typos
npx markdownlint-cli2
script/forbidden_suppressions.sh
```

## Rules

- **No inline suppressions.** Nothing may silence a linter, scanner, type checker, warning or test in place: no
  `rubocop:disable`, `:nocov:`, `:reek:`, `mutant:disable`, `hadolint ignore`, `shellcheck disable`,
  `markdownlint-disable`, `gitleaks:allow`, `nosec`, `T.unsafe`/`T.cast`/`T.bind`/`T.untyped` in `app/`,
  `$VERBOSE = nil`, `skip`/`pending`/`focus`, and so on, and no suppression or todo file (`.rubocop_todo.yml`,
  `.trivyignore`, `.grype.yaml`, `.dockleignore`, `brakeman.ignore`, `sorbet/rbi/todo.rbi`, ...). Fix the cause. A rule
  that cannot apply is configured narrowly in the tool's configuration file, with the reason written next to it
  (`.hadolint.yaml`, `rails_app/.rubocop.yml`, `_typos.toml`, ...).
- **No warnings.** Every workflow ends with a "Warning gate" job (`script/warning_gate.sh`) that fails the run when the
  log of any job contains a warning or a deprecation notice. The output of compiling Ruby, nginx and Passenger inside
  the image build (third-party C code) is kept in the `build.log` of the `image-reports` artifact rather than in the
  job log; the Dockerfile itself is held to zero findings by hadolint and BuildKit's build checks.
- **Behavior is specified.** Every behavioral fix needs a regression test (a spec, a structure test or a smoke-test
  step), and every surviving mutant needs a test that kills it (or, when the mutation cannot change observable
  behavior, simpler code).
- **Vulnerable transitive dependencies are forced to a fixed release.** `package.json` overrides `katex` (needed by
  markdownlint-cli2 through `micromark-extension-math`, whose newest release still asks for `^0.16.0`) to its newest
  release, which fixes CVE-2026-103923; `rake outdated` keeps overrides at the newest release too.
- **Everything is pinned and current.** Docker images are pinned by digest, GitHub Actions by commit, Python tools by
  hash; `rake outdated` keeps them at their newest releases.
