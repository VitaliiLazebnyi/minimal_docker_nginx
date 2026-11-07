# typed: strict
# frozen_string_literal: true

# Copyright (c) 2026 Vitalii Lazebnyi

# Must come first: it has to see warnings emitted while the application and the specs are loaded.
require_relative 'support/warning_guard'

require 'simplecov'

# Mutation runs execute the suite thousands of times against deliberately broken code;
# the coverage gate is meaningless (and noisy) there.
unless defined?(Mutant)
  # Coverage measures the Ruby code of the repository: the application and the scripts of script/. config/ is not
  # tracked: under test only the files of the test environment are loaded, so the development and production
  # configuration could never be covered; the database configuration is specified in spec/rails_app/.
  SimpleCov.root(File.expand_path('../..', __dir__))
  SimpleCov.coverage_dir('rails_app/coverage')
  SimpleCov.cover('rails_app/{app,lib}/**/*.rb', 'script/**/*.rb')
  # Every line, branch and method of every file, not only of the code as a whole.
  %i[line branch method].each do |criterion|
    SimpleCov.coverage(criterion) do |rule|
      rule.minimum(100)
      rule.minimum(100, per: :file)
    end
  end
  SimpleCov.start
end

# Sorbet signatures of the memoized helpers (`sig { returns(...) }` above `let`) and of the helper methods of the
# example groups.
RSpec::Core::ExampleGroup.extend(T::Sig)

RSpec.configure do |config|
  # Enable flags like --only-failures and --next-failure
  config.example_status_persistence_file_path = 'tmp/rspec_status.txt'

  # Disable RSpec exposing methods globally on `Module` and `main`
  config.disable_monkey_patching!
  config.raise_errors_for_deprecations!

  config.expect_with(:rspec) do |expectations|
    expectations.syntax = :expect
    expectations.include_chain_clauses_in_custom_matcher_descriptions = true
  end

  config.mock_with(:rspec) do |mocks|
    mocks.verify_partial_doubles = true
    mocks.verify_doubled_constant_names = true
  end

  config.shared_context_metadata_behavior = :apply_to_host_groups

  # Every Sorbet signature is evaluated before the first example: a signature is otherwise evaluated on the first call
  # of its method, and sorbet-runtime warns when a stub replaces a method whose signature it has not evaluated yet.
  config.before(:suite) { T::Utils.run_all_sig_blocks }

  # Ruby warnings from the project's own files are failures, never noise.
  config.before(:suite) do
    load_time_warnings = WarningGuard.drain
    unless load_time_warnings.empty?
      raise WarningGuard::Violation,
            "Ruby warnings while loading:\n#{load_time_warnings.join}"
    end
  end

  config.after do
    warnings = WarningGuard.drain
    raise WarningGuard::Violation, "Ruby warnings emitted by this example:\n#{warnings.join}" unless warnings.empty?
  end

  # Pending and skipped examples hide missing behavior: the suite must not contain any.
  config.after(:suite) do
    unfinished =
      RSpec.world.all_examples.select do |example|
        example.execution_result.status == :pending || example.skipped? || example.pending?
      end
    unless unfinished.empty?
      raise WarningGuard::Violation,
            "Pending or skipped examples are not allowed:\n#{unfinished.map(&:full_description).join("\n")}"
    end
  end
end
