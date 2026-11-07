# typed: strong
# frozen_string_literal: true

# Copyright (c) 2026 Vitalii Lazebnyi

Rails.application.routes.draw do
  get 'health', to: 'health#show'
  # Rails' own liveness check: 200 when the application boots without exceptions, 500 otherwise.
  get 'up', to: 'rails/health#show', as: :rails_health_check
end
