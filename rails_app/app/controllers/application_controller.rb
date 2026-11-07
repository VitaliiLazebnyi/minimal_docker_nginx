# typed: strict
# frozen_string_literal: true

# Base class of every controller of this API-only application.
class ApplicationController < ActionController::API
  extend T::Sig
end
