# typed: strict
# frozen_string_literal: true

require 'sorbet-runtime'

# The outdated check (script/outdated.rb): shared paths and helpers.
module Outdated
  extend T::Sig

  # The repository root.
  ROOT = T.let(File.expand_path('../..', __dir__), String)
  # The Rails application directory.
  APP = T.let(File.join(ROOT, 'rails_app'), String)
  # Files that pin Docker images, GitHub Actions and Ruby versions.
  PINNING_FILES = T.let(
    [File.join(ROOT, 'Dockerfile'), *Dir[File.join(ROOT, '.github', 'workflows', '*.yml')]].freeze,
    T::Array[String]
  )
  public_constant :ROOT, :APP, :PINNING_FILES

  # Collects the findings of every check.
  class Report
    extend T::Sig

    sig { void }
    def initialize
      @problems = T.let(0, Integer)
    end

    # Prints an informational line.
    # @param message [String]
    sig { params(message: String).void }
    def info(message)
      puts message
    end

    # Prints a message that fails the check.
    # @param message [String]
    sig { params(message: String).void }
    def problem(message)
      warn "OUTDATED: #{message}"
      @problems += 1
    end

    # Reports +used+ as outdated unless it is +newest+.
    # @param label [String] what is compared
    # @param used [String] the version in use
    # @param newest [String] the newest release
    sig { params(label: String, used: String, newest: String).void }
    def compare(label, used, newest)
      if used == newest
        info("#{label} #{used}")
      else
        problem("#{label} #{used} -> #{newest}")
      end
    end

    # The process exit status: 0 when no check failed.
    # @return [Integer]
    sig { returns(Integer) }
    def status
      @problems.zero? ? 0 : 1
    end
  end

  # Paths relative to the repository root, for messages.
  # @param path [String]
  # @return [String]
  sig { params(path: String).returns(String) }
  def self.relative(path)
    path.delete_prefix("#{ROOT}/")
  end

  # The highest of the given version numbers.
  # @param versions [Array<String>]
  # @return [String]
  sig { params(versions: T::Array[String]).returns(String) }
  def self.newest(versions)
    versions.max_by { |version| Gem::Version.new(version) }.to_s
  end
end
