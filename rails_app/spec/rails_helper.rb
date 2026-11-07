# typed: strict
# frozen_string_literal: true

# Copyright (c) 2026 Vitalii Lazebnyi

require 'spec_helper'

# The suite always runs in the test environment, whatever RAILS_ENV says: Rails reads its environment from
# Rails.env (set before the application is loaded) rather than from the process environment.
require 'rails'
Rails.env = 'test'
require_relative '../config/environment'
require 'rspec/rails'

begin
  ActiveRecord::Migration.maintain_test_schema!
rescue ActiveRecord::PendingMigrationError => e
  abort(e.to_s.strip)
end

RSpec.configure do |config|
  config.use_transactional_fixtures = true
  config.infer_spec_type_from_file_location!
  config.filter_rails_from_backtrace!
end
