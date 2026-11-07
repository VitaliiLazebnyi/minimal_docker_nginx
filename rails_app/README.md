# Rails application

The API-only Rails application served by Passenger in the Docker image of this repository (see the
[README](../README.md) of the repository).

- `GET /health` answers `{"status":"OK"}` (probed by the Docker `HEALTHCHECK`).
- `GET /up` is Rails' own liveness check.

Ruby version: `.ruby-version`. Set up and run it locally with `bin/setup`; run every quality gate with
`bundle exec rake` (see [CONTRIBUTING.md](../CONTRIBUTING.md)).
