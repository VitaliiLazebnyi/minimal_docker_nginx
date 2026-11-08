# typed: strong
# frozen_string_literal: true

# Copyright (c) 2026 Vitalii Lazebnyi

require 'sorbet-runtime'
require_relative 'http'
require_relative 'report'

module Outdated
  # Every pinned Ruby must be the newest Ruby, or the newest patch release of a Ruby line on hold.
  class Rubies
    extend T::Sig

    # A Ruby version pinned by a workflow (`ruby-version:`, `check_ruby.sh`) or by the Dockerfile (`ruby:`).
    PIN = /(?:ruby-version: *|ruby:|check_ruby\.sh )["']?(?<version>\d+\.\d+\.\d+)/
    # A stable release of the index of ruby-lang.org: previews and release candidates have a suffix.
    RELEASE = /^ruby-(?<version>\d+\.\d+\.\d+)\t/
    private_constant :PIN, :RELEASE

    # [location, version] of every pinned Ruby.
    # @return [Array<Array(String, String)>]
    sig { returns(T::Array[[String, String]]) }
    def self.pins
      application = File.read(File.join(APP, '.ruby-version')).chomp
      [['rails_app/.ruby-version', application], *PINNING_FILES.flat_map { |path| pins_in(path) }]
    end

    # [location, version] of every Ruby pinned in +path+, each version once.
    # @param path [String]
    # @return [Array<Array(String, String)>]
    sig { params(path: String).returns(T::Array[[String, String]]) }
    def self.pins_in(path)
      versions = Outdated.matches(File.read(path), PIN).map { |match| Outdated.group(match, 'version') }
      versions.uniq!
      versions.map { |version| [Outdated.relative(path), version] }
    end

    # The release line ("3.3") of a version ("3.3.13").
    # @param version [String]
    # @return [String]
    sig { params(version: String).returns(String) }
    def self.line_of(version)
      version.split('.').first(2).join('.')
    end

    # @param report [Report]
    # @param lines [Array<String>] the Ruby lines on hold (e.g. "3.3")
    sig { params(report: Report, lines: T::Array[String]).void }
    def initialize(report, lines)
      @report = report
      @lines = lines
      @index = T.let(Http.body(Http.get('https://cache.ruby-lang.org/pub/ruby/index.txt')), String)
    end

    # Runs the checks.
    sig { void }
    def check
      pins = Rubies.pins
      pins.each { |location, version| check_pin(location, version) }
      check_stale_lines(pins.map { |_, version| Rubies.line_of(version) })
    end

    private

    # Reports every line on hold that no pin uses any more.
    # @param used_lines [Array<String>]
    sig { params(used_lines: T::Array[String]).void }
    def check_stale_lines(used_lines)
      (@lines - used_lines).each { |line| @report.problem("stale hold: no file uses Ruby #{line} any more") }
    end

    # Every stable release of the index of ruby-lang.org.
    # @return [Array<String>]
    sig { returns(T::Array[String]) }
    def releases
      Outdated.matches(@index, RELEASE).map { |match| Outdated.group(match, 'version') }
    end

    # The releases a pin of +line+ is compared with: those of the line when it is on hold, else all.
    # @param line [String]
    # @return [Array<String>]
    sig { params(line: String).returns(T::Array[String]) }
    def releases_for(line)
      @lines.include?(line) ? releases.select { |release| Rubies.line_of(release) == line } : releases
    end

    # Reports the pinned Ruby unless it is the newest release it is compared with.
    # @param location [String]
    # @param version [String]
    sig { params(location: String, version: String).void }
    def check_pin(location, version)
      line = Rubies.line_of(version)
      held = ', line on hold' if @lines.include?(line)
      @report.compare("Ruby (#{location}#{held})", version, Outdated.newest(releases_for(line)))
    end
  end
end
