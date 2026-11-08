# typed: strong
# frozen_string_literal: true

# Copyright (c) 2026 Vitalii Lazebnyi

require 'open3'
require 'sorbet-runtime'
require_relative 'document'
require_relative 'error'
require_relative 'http'
require_relative 'report'

module Outdated
  # The gems and Bundler of rails_app/, the RubyGems and Passenger versions the Dockerfile installs.
  class Bundle
    extend T::Sig

    # A line of `bundle outdated --parseable`: the gem, its newest release and the installed version.
    OUTDATED_LINE = /^(?<name>\S+) \(newest (?<newest>[^,\s]+), installed (?<installed>[^,)\s]+)/
    private_constant :OUTDATED_LINE

    # [name, newest, installed] of every gem `bundle outdated` reports.
    # @return [Array<Array(String, String, String)>]
    # @raise [Error] when `bundle outdated` cannot check
    sig { returns(T::Array[[String, String, String]]) }
    def self.outdated_gems
      output, status = bundle_outdated
      # Exit status 1 only means that some gem is outdated; a killed process has no exit status.
      code = status.exitstatus || 2
      raise(Error, "bundle outdated failed (#{code}):\n#{output}") if code > 1

      Outdated.matches(output, OUTDATED_LINE).map do |match|
        [Outdated.group(match, 'name'), Outdated.group(match, 'newest'), Outdated.group(match, 'installed')]
      end
    end

    # Runs `bundle outdated --parseable` in rails_app/.
    # @return [Array(String, Process::Status)] its output (standard output and error) and its exit status
    sig { returns([String, Process::Status]) }
    def self.bundle_outdated
      # `bundle outdated` refuses to run in deployment mode (which CI's setup-ruby configures); it only reads the
      # lockfile and the gem index, so it runs with deployment and frozen mode off.
      Open3.capture2e(
        { 'BUNDLE_DEPLOYMENT' => 'false', 'BUNDLE_FROZEN' => 'false' },
        'bundle',
        'outdated',
        '--parseable',
        chdir: APP
      )
    end

    # @param report [Report]
    # @param holds [Hash{String => String}] held gem name => the newest release it is held back from
    sig { params(report: Report, holds: T::Hash[String, String]).void }
    def initialize(report, holds)
      @report = report
      @holds = holds
      @lockfile = T.let(File.read(File.join(APP, 'Gemfile.lock')), String)
    end

    # Runs the checks.
    sig { void }
    def check
      check_gems
      check_bundler
      check_rubygems
      check_passenger
    end

    private

    # Reports every outdated gem that is not held, and every hold of a gem that is no longer outdated.
    sig { void }
    def check_gems
      outdated = Bundle.outdated_gems
      outdated.each { |name, newest, installed| check_gem(name, newest, installed) }
      (@holds.keys - outdated.map(&:first)).each do |name|
        @report.problem("stale hold: gem #{name} is no longer outdated")
      end
    end

    # Reports an outdated gem: informational when it is held back from exactly +newest+, else a problem.
    # @param name [String]
    # @param newest [String]
    # @param installed [String]
    sig { params(name: String, newest: String, installed: String).void }
    def check_gem(name, newest, installed)
      if @holds[name] == newest
        @report.info("gem #{name} #{installed} (newest #{newest}, on hold)")
      else
        @report.problem("gem #{name} #{installed} -> #{newest} is not on the hold list")
      end
    end

    # The Bundler of Gemfile.lock (BUNDLED WITH) must be the newest.
    sig { void }
    def check_bundler
      newest = Document.string(Http.json('https://rubygems.org/api/v1/versions/bundler/latest.json'), ['version'])
      used = Outdated.extract(@lockfile, /^BUNDLED WITH\n\s+(?<value>\S+)/)
      @report.compare('Bundler (Gemfile.lock, BUNDLED WITH)', used, newest)
    end

    # The RubyGems the Dockerfile installs must be the newest.
    sig { void }
    def check_rubygems
      newest = Document.string(
        Http.json('https://rubygems.org/api/v1/versions/rubygems-update/latest.json'),
        ['version']
      )
      @report.compare('RubyGems (Dockerfile ARG RUBYGEMS_VERSION)', Outdated.dockerfile_arg('RUBYGEMS_VERSION'), newest)
    end

    # The Passenger the Dockerfile builds must be the one of Gemfile.lock.
    sig { void }
    def check_passenger
      locked = Outdated.extract(@lockfile, /^    passenger \((?<value>[^)]+)\)/)
      @report.compare(
        'Passenger (Dockerfile ARG PASSENGER_VERSION, must match Gemfile.lock)',
        Outdated.dockerfile_arg('PASSENGER_VERSION'),
        locked
      )
    end
  end
end
