class HealthController < ApplicationController
  def show
    render json: { status: 'OK' }, status: :ok
  end
end
