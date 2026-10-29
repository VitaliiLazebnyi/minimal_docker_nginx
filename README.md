# minimal_docker_nginx

A minimal `FROM scratch` Docker image that serves a Ruby on Rails API application with nginx and Phusion Passenger
(see [REQUIREMENTS.md](REQUIREMENTS.md)). The builder stage compiles Ruby, nginx and Passenger with aggressive
optimization flags, then copies only what the running application needs into an empty image
([DOCKER_MINIMIZATION.md](DOCKER_MINIMIZATION.md), [OPTIMIZATION_INSIGHTS.md](OPTIMIZATION_INSIGHTS.md)).

| Component | Version |
| --- | --- |
| Base image (builder) | `ruby:4.0.9-alpine3.24`, pinned by digest |
| Ruby | 4.0.9 (recompiled from the verified source tarball of the base image), RubyGems 4.0.23 |
| Rails | 8.1.4 |
| Passenger | 6.2.1 |
| nginx | 1.31.8, the newest release (source tarball verified against its SHA-256) |

## Running the image

```bash
docker build --tag minimal-docker-nginx .
docker run --rm --publish 8080:80 minimal-docker-nginx
curl http://localhost:8080/health   # {"status":"OK"}
```

- `GET /health` answers `{"status":"OK"}`; the Docker `HEALTHCHECK` probes it with BusyBox `wget`.
- nginx, Passenger and the application run as the unprivileged user `app` (uid 10001). nginx still listens on port 80:
  Docker sets `net.ipv4.ip_unprivileged_port_start=0` in every container. On a runtime that does not (for example a
  Kubernetes pod without that sysctl), set it in the pod's `securityContext.sysctls`.
- Set `SECRET_KEY_BASE` (for example `--env SECRET_KEY_BASE=$(openssl rand -hex 64)`) when signed or encrypted data
  must survive a restart; without it, each container generates its own at start.
- Every log is written under `/var/logs` (nginx, Passenger, and `logrotate.log`); logs are rotated every day at
  midnight UTC.
- The binaries are compiled with `-march=native` (REQ-COMP-001): build the image on the CPU model it will run on.

## Quality gates

Every gate runs in CI and fails the build; every workflow ends with a warning gate that fails when the log of any of
its jobs contains a warning or a deprecation notice. See [CONTRIBUTING.md](CONTRIBUTING.md) for how to run them locally.

| Workflow | Gates |
| --- | --- |
| CI | RSpec with 100% line and branch coverage, RuboCop (rails, rspec, performance, sorbet, ... plugins), Sorbet `typed: strict`, YARD 100% documented, Reek, Flay, outdated dependencies |
| Mutation testing | Mutant on every subject of `app/`; every mutant must be killed |
| Docker image | hadolint, BuildKit build checks, Trivy misconfiguration scan, container-structure-test, an end-to-end smoke test, Dockle, Trivy and Grype (fail on any fixable vulnerability), `nginx -t`, gixy |
| Security | bundler-audit, Brakeman, Trivy (lockfiles and secrets), dependency review with an OpenSSF Scorecard gate (per-package allowances), gitleaks (full history) |
| Lint | actionlint, zizmor (pedantic), ShellCheck (every optional check), typos, rumdl (markdownlint rules), no inline suppressions |

The vulnerability reports of the image (Trivy, Grype) and the list of its files are uploaded as the `image-reports`
artifact of every run of the Docker image workflow.
