# minimal_docker_nginx

A minimal `FROM scratch` Docker image that serves a Ruby on Rails API application with nginx and Phusion Passenger
(see [REQUIREMENTS.md](REQUIREMENTS.md)). The builder stage compiles Ruby, nginx and Passenger with aggressive
optimization flags, then copies only what the running application needs into an empty image
([DOCKER_MINIMIZATION.md](DOCKER_MINIMIZATION.md), [OPTIMIZATION_INSIGHTS.md](OPTIMIZATION_INSIGHTS.md)).

| Component | Version |
| --- | --- |
| Base image (builder) | `ruby:4.0.9-alpine3.24`, pinned by digest |
| Ruby | 4.0.9 (recompiled from the verified source tarball of the base image), RubyGems 4.0.24 |
| Rails | 8.1.4.1 |
| Passenger | 6.2.1 |
| nginx | 1.31.8, the newest release (source tarball verified against its SHA-256) |

## Running the Image

```bash
docker build --tag minimal-docker-nginx .
docker run --rm --publish 8080:80 minimal-docker-nginx
curl http://localhost:8080/health   # {"status":"OK"}
```

- `GET /health` answers `{"status":"OK"}`; the Docker `HEALTHCHECK` probes it with BusyBox `wget`.
- nginx, Passenger and the application run as the unprivileged user `app` (uid 10001). nginx still listens on port 80:
  Docker sets `net.ipv4.ip_unprivileged_port_start=0` in every container. On a runtime that does not (for example a
  Kubernetes pod without that sysctl), set it in the pod's `securityContext.sysctls`.
- The database is a SQLite file under `/app/storage`, configured by `DATABASE_URL` (mount a volume there to keep it).
- Set `SECRET_KEY_BASE` (for example `--env SECRET_KEY_BASE=$(openssl rand -hex 64)`) when signed or encrypted data
  must survive a restart; without it, each container generates its own at start.
- Every log is written under `/var/logs` (nginx, Passenger, and `logrotate.log`); logs are rotated every day at
  midnight UTC.
- The binaries are compiled with `-march=native` (REQ-COMP-001): build the image on the CPU model it will run on.

## Quality Gates

Every gate runs in CI on every pull request and on every push to `main`, through `script/check` (which runs the same
checks locally, see [CONTRIBUTING.md](CONTRIBUTING.md)); every workflow ends with a warning gate that fails when the log
of any of its jobs contains a warning or a deprecation notice, and every job runs behind an egress allow-list.

- **CI**: RSpec with 100% line and branch coverage; RuboCop with every cop of RuboCop and of its plugins
  (`rubocop-rails`, `rubocop-rspec`, `rubocop-rspec_rails`, `rubocop-performance`, `rubocop-rake`, `rubocop-sorbet`,
  `rubocop-thread_safety`, `rubocop-yard`, `rubocop-md`, `rubocop-ai`); Sorbet (`typed: strong` for the application
  and the scripts); YARD 100% documented without warnings; Reek, Flay, Flog and debride; outdated dependencies.
- **Mutation testing**: Mutant on every subject of `app/`; every mutant must be killed.
- **Docker image**: hadolint (every severity), BuildKit build checks, the Trivy misconfiguration scan,
  container-structure-test, an end-to-end smoke test, Dockle, Trivy and Grype (fail on any fixable vulnerability),
  `nginx -t` and gixy.
- **Security**: bundler-audit, Brakeman, Trivy (lockfiles and secrets), dependency review with an OpenSSF Scorecard
  gate (per-package allowances), gitleaks (full history).
- **Lint**: actionlint, zizmor (pedantic), ShellCheck (every optional check), shfmt, typos, rumdl (every rule),
  yamllint (every rule, strict), editorconfig-checker, no inline suppressions.
- **CodeQL**: the Ruby code and the workflows, with the security-extended and security-and-quality suites.
- **OpenSSF Scorecard** (on `main`): published to the Scorecard API and to code scanning.

The vulnerability reports of the image (Trivy, Grype) and the list of its files are uploaded as the `image-reports`
artifact of every run of the Docker image workflow.
