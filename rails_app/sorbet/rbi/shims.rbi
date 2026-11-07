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
  include ::RSpec::Matchers
  include ::RSpec::Mocks::ExampleMethods
  include ::RSpec::Rails::Matchers
  include ::RSpec::Rails::RequestExampleGroup

  # The response of the last request, which ActionDispatch::Integration::Runner delegates (through
  # method_missing) to its integration session.
  sig { returns(::ActionDispatch::TestResponse) }
  def response; end
end
