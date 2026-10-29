# typed: strict
# frozen_string_literal: true

require 'open3'
require 'sorbet-runtime'
require_relative 'document'
require_relative 'http'
require_relative 'report'

module Outdated
  # The gems and Bundler of rails_app/, the RubyGems and Passenger versions the Dockerfile installs.
  class Bundle
    extend T::Sig

    OUTDATED_LINE = /^(\S+) \(newest ([^,\s]+), installed ([^,)\s]+)/
    private_constant :OUTDATED_LINE

    # [name, newest, installed] of every gem `bundle outdated` reports; raises when it cannot check.
    # @return [Array<(String, String, String)>]
    sig { returns(T::Array[[String, String, String]]) }
    def self.outdated_gems
      # `bundle outdated` refuses to run in deployment mode (which CI's setup-ruby configures); it only reads the
      # lockfile and the gem index, so it runs with deployment and frozen mode off.
      output, status = Open3.capture2e({ 'BUNDLE_DEPLOYMENT' => 'false', 'BUNDLE_FROZEN' => 'false' },
                                       'bundle', 'outdated', '--parseable', chdir: APP)
      # Exit status 1 only means that some gem is outdated; a killed process has no exit status.
      code = status.exitstatus || 2
      raise "bundle outdated failed (#{code}):\n#{output}" if code > 1

      output.scan(OUTDATED_LINE).map { |name, newest, installed| [name.to_s, newest.to_s, installed.to_s] }
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

    sig { void }
    def check_gems
      outdated = Bundle.outdated_gems
      outdated.each { |name, newest, installed| check_gem(name, newest, installed) }
      (@holds.keys - outdated.map(&:first)).each do |name|
        @report.problem("stale hold: gem #{name} is no longer outdated")
      end
    end

    sig { params(name: String, newest: String, installed: String).void }
    def check_gem(name, newest, installed)
      if @holds[name] == newest
        @report.info("gem #{name} #{installed} (newest #{newest}, on hold)")
      else
        @report.problem("gem #{name} #{installed} -> #{newest} is not on the hold list")
      end
    end

    sig { void }
    def check_bundler
      newest = Document.string(Http.json('https://rubygems.org/api/v1/versions/bundler/latest.json'), ['version'])
      @report.compare('Bundler (Gemfile.lock, BUNDLED WITH)', @lockfile[/^BUNDLED WITH\n\s+(\S+)/, 1].to_s, newest)
    end

    sig { void }
    def check_rubygems
      newest = Document.string(Http.json('https://rubygems.org/api/v1/versions/rubygems-update/latest.json'),
                               ['version'])
      built = File.read(File.join(ROOT, 'Dockerfile'))[/^ARG RUBYGEMS_VERSION=(\S+)/, 1].to_s
      @report.compare('RubyGems (Dockerfile ARG RUBYGEMS_VERSION)', built, newest)
    end

    sig { void }
    def check_passenger
      built = File.read(File.join(ROOT, 'Dockerfile'))[/^ARG PASSENGER_VERSION=(\S+)/, 1].to_s
      locked = @lockfile[/^    passenger \(([^)]+)\)/, 1].to_s
      @report.compare('Passenger (Dockerfile ARG PASSENGER_VERSION, must match Gemfile.lock)', built, locked)
    end
  end
end
