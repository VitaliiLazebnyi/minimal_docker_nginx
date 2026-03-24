# System Requirements (Single Source of Truth)

## Meta Constraints
- **REQ-DOC-001**: Automatically scaffold a `REQUIREMENTS.md` file at the root of formal projects.
- **REQ-DOC-002**: Defect Tracking in a dedicated `BUGS.md` file. Zero historic bug logs in active specifications.
- **REQ-CODE-001**: 100% Test Coverage Mandate. Zero warnings and zero errors from linters/static analysis.
- **REQ-UNIT-001**: Strictly utilize the Metric system internally.
- **REQ-TZ-001**: Strictly default to UTC internally.

## Application Architecture
- **REQ-APP-001**: Build minimal possible Docker image using `FROM scratch` technique.
- **REQ-APP-002**: Contain fully functional Ruby on Rails application.
- **REQ-APP-003**: The Rails application must serve a special endpoint to confirm health status.
- **REQ-WEB-001**: Use Nginx as a web server with Passenger.
- **REQ-WEB-002**: Use the latest available versions of Nginx, RoR, and Passenger on their official websites.

## Application Compilation (C/C++)
- **REQ-COMP-001**: Enforce absolute maximum native CPU throughput by explicitly binding `CFLAGS` and `CXXFLAGS` to `-Ofast`, `-march=native`, and `-flto` (Link Time Optimization) across all standard dependencies.

## System Configuration
- **REQ-LOG-001**: Every single log must be written to `/var/logs/` or its subfolder.
- **REQ-LOG-002**: Configure `logrotate` to trigger at midnight.
- **REQ-DOCKER-001**: Docker `HEALTHCHECK` must leverage the native BusyBox `wget --spider` command. Utilizing `curl` is strictly prohibited as it bloats the final `scratch` geometry by `>1MB`.

## Optimization Strategies
- **REQ-MIN-001**: The specific techniques from `DOCKER_MINIMIZATION.md` will be applied.
- **REQ-MIN-002**: Output image will strictly exclude unreachable files, OS metadata, and unneeded compilers.
