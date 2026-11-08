# typed: strong
# frozen_string_literal: true

# Copyright (c) 2026 Vitalii Lazebnyi

require 'sorbet-runtime'
require_relative 'error'

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

    # @param prefix [String] the word that starts every failing message
    sig { params(prefix: String).void }
    def initialize(prefix = 'OUTDATED')
      @prefix = prefix
      @problems = T.let(0, Integer)
    end

    # The number of problems reported so far.
    # @return [Integer]
    sig { returns(Integer) }
    attr_reader :problems

    # Prints an informational line.
    # @param message [String]
    sig { params(message: String).void }
    def info(message)
      puts(message)
    end

    # Prints a message that fails the check.
    # @param message [String]
    sig { params(message: String).void }
    def problem(message)
      warn("#{@prefix}: #{message}")
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
      problems.zero? ? 0 : 1
    end
  end

  # Paths relative to the repository root, for messages.
  # @param path [String]
  # @return [String]
  sig { params(path: String).returns(String) }
  def self.relative(path)
    path.delete_prefix("#{ROOT}/")
  end

  # The highest of the given version numbers ("" when there is none).
  # @param versions [Array<String>]
  # @return [String]
  sig { params(versions: T::Array[String]).returns(String) }
  def self.newest(versions)
    versions.max_by { |version| Gem::Version.new(version) }
            .to_s
  end

  # The match of +regex+ in each line of +text+ that has one.
  # @param text [String]
  # @param regex [Regexp]
  # @return [Array<MatchData>]
  sig { params(text: String, regex: Regexp).returns(T::Array[MatchData]) }
  def self.matches(text, regex)
    text.each_line.filter_map { |line| regex.match(line) }
  end

  # The text of the named group +name+ of +match+.
  # @param match [MatchData]
  # @param name [String]
  # @return [String]
  # @raise [Error] when the group took no part in the match
  sig { params(match: MatchData, name: String).returns(String) }
  def self.group(match, name)
    match[name] || raise(Error, "#{match.regexp.inspect} matched #{match.to_s.inspect} without #{name}")
  end

  # The group `value` of the first match of +regex+ in +text+.
  # @param text [String]
  # @param regex [Regexp] a pattern with a group named `value`
  # @return [String]
  # @raise [Error] when +text+ has no match
  sig { params(text: String, regex: Regexp).returns(String) }
  def self.extract(text, regex)
    match = regex.match(text)
    raise(Error, "no match of #{regex.inspect}") unless match

    group(match, 'value')
  end

  # The value of the build argument +name+ in the Dockerfile.
  # @param name [String]
  # @return [String]
  # @raise [Error] when the Dockerfile has no such ARG
  sig { params(name: String).returns(String) }
  def self.dockerfile_arg(name)
    extract(File.read(File.join(ROOT, 'Dockerfile')), /^ARG #{name}=(?<value>\S+)$/)
  end
end
