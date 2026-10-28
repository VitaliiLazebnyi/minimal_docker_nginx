# typed: false
# frozen_string_literal: true

# Must come first: it has to see warnings emitted while the application and the specs are loaded.
require_relative 'support/warning_guard'

require 'simplecov'

# Mutation runs execute the suite thousands of times against deliberately broken code;
# the coverage gate is meaningless (and noisy) there.
unless defined?(Mutant)
  SimpleCov.start do
    enable_coverage :branch
    minimum_coverage line: 100, branch: 100
    # Coverage measures the application code. config/ is not tracked: under test only the
    # files of the test environment are loaded, so the development and production
    # configuration could never be covered; the database configuration is specified in spec/rails_app/.
    cover '{app,lib}/**/*.rb'
  end
end

RSpec.configure do |config|
  # Enable flags like --only-failures and --next-failure
  config.example_status_persistence_file_path = 'tmp/rspec_status.txt'

  # Disable RSpec exposing methods globally on `Module` and `main`
  config.disable_monkey_patching!
  config.raise_errors_for_deprecations!

  config.expect_with :rspec do |expectations|
    expectations.syntax = :expect
    expectations.include_chain_clauses_in_custom_matcher_descriptions = true
  end

  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
    mocks.verify_doubled_constant_names = true
  end

  config.shared_context_metadata_behavior = :apply_to_host_groups

  # Ruby warnings from the project's own files are failures, never noise.
  config.before(:suite) do
    load_time_warnings = WarningGuard.drain
    raise "Ruby warnings while loading:\n#{load_time_warnings.join}" unless load_time_warnings.empty?
  end

  config.after do
    warnings = WarningGuard.drain
    raise "Ruby warnings emitted by this example:\n#{warnings.join}" unless warnings.empty?
  end

  # Pending and skipped examples hide missing behavior: the suite must not contain any.
  config.after(:suite) do
    unfinished = RSpec.world.all_examples.select do |example|
      example.execution_result.status == :pending || example.skipped? || example.pending?
    end
    unless unfinished.empty?
      raise "Pending or skipped examples are not allowed:\n#{unfinished.map(&:full_description).join("\n")}"
    end
  end
end
