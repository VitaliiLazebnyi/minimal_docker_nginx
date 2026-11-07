# typed: strong
# frozen_string_literal: true

# Copyright (c) 2026 Vitalii Lazebnyi

module Outdated
  # Raised when a dependency cannot be checked because a command or a request failed.
  class Error < StandardError; end
end
