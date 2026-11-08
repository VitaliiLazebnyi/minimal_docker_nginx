# typed: strict

# Copyright (c) 2026 Vitalii Lazebnyi

# Bundler vendors connection_pool as Bundler::ConnectionPool, whose fork tracker extends Process while Tapioca
# runs; the generated RBI of sqlite3 (which also extends Process) records that mixin, so Sorbet must know it.
class Bundler::ConnectionPool; end
module Bundler::ConnectionPool::ForkTracker; end

# RSpec mixes its matcher and mock DSLs into every example group at runtime (`config.expect_with` and
# `config.mock_with` in spec/spec_helper.rb), and rspec-rails its request-spec DSL into the request specs
# (`config.infer_spec_type_from_file_location!` in spec/rails_helper.rb); Sorbet's RSpec support needs the same
# ancestry declared.
class RSpec::Core::ExampleGroup
  # spec/spec_helper.rb: the signatures of the memoized helpers and helper methods of the example groups.
  extend T::Sig

  # Included before RSpec::Matchers, whose #expect (which also takes a block) takes precedence over the #expect of
  # rspec-mocks, as it does at runtime.
  include ::RSpec::Mocks::ExampleMethods
  include ::RSpec::Matchers
  include ::RSpec::Rails::Matchers
  include ::RSpec::Rails::RequestExampleGroup

  # The response of the last request, which ActionDispatch::Integration::Runner delegates (through
  # method_missing) to its integration session.
  sig { returns(::ActionDispatch::TestResponse) }
  def response; end
end
