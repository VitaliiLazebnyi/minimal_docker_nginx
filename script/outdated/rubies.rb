# typed: strict
# frozen_string_literal: true

require 'sorbet-runtime'
require_relative 'http'
require_relative 'report'

module Outdated
  # Every pinned Ruby must be the newest Ruby, or the newest patch release of a Ruby line on hold.
  class Rubies
    extend T::Sig

    PIN = /(?:ruby-version: *|ruby:|check_ruby\.sh )["']?(\d+\.\d+\.\d+)/
    private_constant :PIN

    # [location, version] of every pinned Ruby.
    # @return [Array<(String, String)>]
    sig { returns(T::Array[[String, String]]) }
    def self.pins
      application = T.let([['rails_app/.ruby-version', File.read(File.join(APP, '.ruby-version')).strip]],
                          T::Array[[String, String]])
      application + PINNING_FILES.flat_map { |path| pins_in(path) }
    end

    # [location, version] of every Ruby pinned in +path+.
    # @param path [String]
    # @return [Array<(String, String)>]
    sig { params(path: String).returns(T::Array[[String, String]]) }
    def self.pins_in(path)
      versions = File.read(path).scan(PIN).flatten
      versions.uniq!
      versions.map { |version| [Outdated.relative(path), version.to_s] }
    end

    # The release line ("3.3") of a version ("3.3.13").
    # @param version [String]
    # @return [String]
    sig { params(version: String).returns(String) }
    def self.line_of(version)
      version[/\A\d+\.\d+/].to_s
    end

    # @param report [Report]
    # @param lines [Array<String>] the Ruby lines on hold (e.g. "3.3")
    sig { params(report: Report, lines: T::Array[String]).void }
    def initialize(report, lines)
      @report = report
      @lines = lines
      index = Http.get('https://cache.ruby-lang.org/pub/ruby/index.txt').body.to_s
      # Stable releases only: previews and release candidates have a suffix.
      releases = index.scan(/^ruby-(\d+\.\d+\.\d+)\t/).flatten
      releases.uniq!
      @releases = T.let(releases.map(&:to_s), T::Array[String])
    end

    # Runs the checks.
    sig { void }
    def check
      pins = Rubies.pins
      pins.each { |location, version| check_pin(location, version) }
      check_stale_lines(pins.map { |_, version| Rubies.line_of(version) })
    end

    private

    sig { params(used_lines: T::Array[String]).void }
    def check_stale_lines(used_lines)
      (@lines - used_lines).each { |line| @report.problem("stale hold: no file uses Ruby #{line} any more") }
    end

    # The releases a pin of +line+ is compared with: those of the line when it is on hold, else all.
    sig { params(line: String).returns(T::Array[String]) }
    def releases_for(line)
      @lines.include?(line) ? @releases.select { |release| Rubies.line_of(release) == line } : @releases
    end

    sig { params(location: String, version: String).void }
    def check_pin(location, version)
      line = Rubies.line_of(version)
      held = ', line on hold' if @lines.include?(line)
      @report.compare("Ruby (#{location}#{held})", version, Outdated.newest(releases_for(line)))
    end
  end
end
