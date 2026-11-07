# typed: false
# frozen_string_literal: true

Rails.application.routes.draw do
  get 'health', to: 'health#show'
  # Rails' own liveness check: 200 when the application boots without exceptions, 500 otherwise.
  get 'up', to: 'rails/health#show', as: :rails_health_check
end
