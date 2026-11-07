# typed: strong
# frozen_string_literal: true

# Copyright (c) 2026 Vitalii Lazebnyi

require 'sorbet-runtime'

# Turns every Ruby warning raised from this project's own code (app/, config/, lib/ and spec/)
# into a test failure. Warnings that originate in third-party gems are left to Ruby's default
# handling, and CI's warning gate fails the run on any of them that reaches a log.
module WarningGuard
  extend T::Sig

  # Raised when the suite breaks one of its own rules: a Ruby warning from the project, or a pending or
  # skipped example.
  class Violation < StandardError; end

  PROJECT_ROOT = T.let(File.expand_path('../..', __dir__), String)
  OWN_DIRECTORIES = T.let(
    %w[app config lib spec].map { |directory| File.join(PROJECT_ROOT, directory) }
    .freeze,
    T::Array[String]
  )
  LOCATION = /\A(?<path>[^:\n]+\.rb):\d+/
  COLLECTED = Thread::Queue.new
  public_constant :PROJECT_ROOT, :OWN_DIRECTORIES, :LOCATION, :COLLECTED

  # Returns and forgets the warnings collected so far.
  # @return [Array<String>]
  sig { returns(T::Array[String]) }
  def self.drain
    Array.new(COLLECTED.size) { T.let(COLLECTED.pop, String) }
  end

  # Whether +message+ names a file inside one of this project's own directories.
  # @param message [String] a Ruby warning message
  # @return [Boolean]
  sig { params(message: String).returns(T::Boolean) }
  def self.own?(message)
    path = message[LOCATION, :path]
    return false unless path

    expanded = File.expand_path(path)
    OWN_DIRECTORIES.any? { |directory| expanded.start_with?("#{directory}/") }
  end

  # Records warnings coming from this project, then defers to Ruby's default handling.
  # @param message [String]
  # @param category [Symbol, nil] the category of the warning (:deprecated, :experimental, :performance)
  # @return [void]
  sig { params(message: String, category: T.nilable(Symbol)).void }
  def warn(message, category: nil)
    COLLECTED << message if WarningGuard.own?(message)
    super
  end
end

Warning[:deprecated] = true
Warning[:experimental] = true
Warning[:performance] = true
Warning.singleton_class.prepend(WarningGuard)
