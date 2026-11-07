# typed: strong
# frozen_string_literal: true

# Copyright (c) 2026 Vitalii Lazebnyi

# Loading ActiveSupport::Configurable prints a deprecation notice (Rails 8.1 deprecates it without
# replacement), and Tapioca loads every constant it finds while it compiles the RBIs. Neither this application nor
# any of its dependencies uses that module, so its autoload is removed (without loading it) before the
# RBIs are compiled.
ActiveSupport.__send__(:remove_const, :Configurable) if ActiveSupport.autoload?(:Configurable)

# RSpec's gems are loaded by the suite (spec/rails_helper.rb), not by Bundler.require: they are required here so
# that Tapioca compiles their RBIs, which Sorbet's RSpec support types the specs with.
# The test helpers rspec-rails mixes into its example groups are not loaded by anything else either.
require 'active_support/current_attributes/test_helper'
require 'active_support/execution_context/test_helper'
require 'rspec/core'
require 'rspec/expectations'
require 'rspec/mocks'
require 'rspec/rails'
