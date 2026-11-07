# typed: strict
# frozen_string_literal: true

# Copyright (c) 2026 Vitalii Lazebnyi

# Run using bin/ci: the same gates as `bundle exec rake` (see CONTRIBUTING.md), one step per gate.
ActiveSupport::ContinuousIntegration.run do |ci|
  ci.step('Setup', 'bin/setup --skip-server')
  ci.step('Gates', 'bin/rake')
end
