# typed: strict
# frozen_string_literal: true

# Health endpoint probed by the Docker HEALTHCHECK (REQ-APP-003).
class HealthController < ApplicationController
  # The body of every health response; the HEALTHCHECK greps it for "OK".
  HEALTHY = T.let({ status: 'OK' }.freeze, T::Hash[Symbol, String])
  public_constant :HEALTHY

  # GET /health: answers 200 with {"status":"OK"} once the application has booted.
  sig { void }
  def show
    render json: HEALTHY
  end
end
