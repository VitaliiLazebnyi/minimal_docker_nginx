# typed: strict
# frozen_string_literal: true

require 'sorbet-runtime'
require_relative 'git_tags'
require_relative 'report'

module Outdated
  # The nginx release Passenger builds must be the newest stable release (and the newest release, or held).
  class Nginx
    extend T::Sig

    # The nginx version passenger-install-nginx-module downloads (and verifies the checksum of).
    # @return [String]
    sig { returns(String) }
    def self.passenger_preferred
      gem_dir = Gem::Specification.find_by_name('passenger').gem_dir
      source = File.read(File.join(gem_dir, 'src', 'ruby_supportlib', 'phusion_passenger.rb'))
      source[/^\s*PREFERRED_NGINX_VERSION\s*=\s*'([^']+)'/, 1].to_s
    end

    # @param report [Report]
    # @param hold [String, nil] the newest release nginx is held back from, when it is on hold
    sig { params(report: Report, hold: T.nilable(String)).void }
    def initialize(report, hold)
      @report = report
      @hold = hold
      tags = GitTags.of('https://github.com/nginx/nginx').keys
      @releases = T.let(tags.filter_map { |tag| tag[/\Arelease-(\d+\.\d+\.\d+)\z/, 1] }, T::Array[String])
    end

    # Runs the checks.
    sig { void }
    def check
      built = Nginx.passenger_preferred
      # nginx numbers its stable branches with an even minor version, its mainline branch with an odd one.
      stable = Outdated.newest(@releases.select { |release| Integer(release.split('.').fetch(1), 10).even? })
      @report.compare('nginx (built by Passenger, newest stable release)', built, stable)
      check_hold(built, Outdated.newest(@releases))
    end

    private

    sig { params(built: String, newest: String).void }
    def check_hold(built, newest)
      if built == newest
        @report.problem('stale hold: nginx is at its newest release') if @hold
      elsif @hold == newest
        @report.info("nginx #{built} (newest #{newest}, on hold)")
      else
        @report.problem("nginx #{built} -> #{newest} is not on the hold list")
      end
    end
  end
end
