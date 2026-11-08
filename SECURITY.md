# Security Policy

How to report a vulnerability of the image or of the application it serves, and how the repository guards its
supply chain.

## Supported Versions

Security fixes are made on the `main` branch, from which the image is built. There are no maintained release branches.

## Reporting a Vulnerability

Please report a suspected vulnerability privately rather than in a public issue: use the **Report a vulnerability**
button of the repository's [Security tab](https://github.com/VitaliiLazebnyi/minimal_docker_nginx/security) (private
vulnerability reporting).

Include a description of the issue, the affected commit and, if possible, a minimal reproduction. You can expect an
acknowledgement within a few business days. Once a fix is merged, the advisory is published.

## Scope

The image runs nginx with Passenger, which serves the Rails application of `rails_app/` (see
[README.md](README.md)). Both the application and the build of the image are in scope.

## Supply-Chain Safeguards

Every pull request runs the checks of [CONTRIBUTING.md](CONTRIBUTING.md): among them bundler-audit, Brakeman,
Semgrep, dependency review (any severity), gitleaks over the whole history, Trivy and Grype on the lockfiles and the
image, CodeQL and zizmor; the OpenSSF Scorecard runs on the default branch. Every job runs behind a network egress
allow list (`step-security/harden-runner`). Every GitHub Action is pinned to a full commit SHA, every Docker image to
its digest, every Python tool to its hash and every downloaded binary to its SHA-256; Dependabot proposes updates
after a one-week cooldown.
