# typed: false
# frozen_string_literal: true

# Run using bin/ci: the same gates as `bundle exec rake` (see CONTRIBUTING.md), one step per gate.
ActiveSupport::ContinuousIntegration.run do
  step 'Setup', 'bin/setup --skip-server'
  step 'Gates', 'bin/rake'
end
