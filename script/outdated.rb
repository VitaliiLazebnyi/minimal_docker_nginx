#!/usr/bin/env ruby
# typed: strict
# frozen_string_literal: true

# Fails when a dependency of this repository is not at its newest release and is not on the documented hold
# list (script/outdated_holds.yml), or when a listed hold is no longer needed. It covers the gems and Bundler
# of rails_app/, RubyGems, every pinned Ruby, the nginx release the image builds, the Docker images (tag and digest) of
# the Dockerfile and the workflows, the GitHub Actions (tag and commit), and the Python and npm tools.
#
# Run it with `bundle exec rake outdated` in rails_app/: it needs the application bundle (`bundle outdated`
# and the installed Passenger gem).

require 'sorbet-runtime'
require 'yaml'

require_relative 'outdated/actions'
require_relative 'outdated/bundle'
require_relative 'outdated/document'
require_relative 'outdated/images'
require_relative 'outdated/nginx'
require_relative 'outdated/report'
require_relative 'outdated/rubies'
require_relative 'outdated/tools'

# The outdated check; see the header of this file.
module Outdated
  extend T::Sig

  # Runs every check and returns the process exit status.
  # @return [Integer]
  sig { returns(Integer) }
  def self.run
    report = Report.new
    checks(report, YAML.safe_load_file(File.join(ROOT, 'script', 'outdated_holds.yml'))).each(&:check)
    report.status
  end

  # The checks, each given the holds of its kind of dependency.
  # @param report [Report]
  # @param holds [Object] the parsed script/outdated_holds.yml
  # @return [Array<#check>]
  sig { params(report: Report, holds: Object).returns(T::Array[T.any(Bundle, Rubies, Nginx, Images, Actions, Tools)]) }
  def self.checks(report, holds)
    held_gems = Document.keys(holds, ['gems']).to_h { |name| [name, Document.string(holds, ['gems', name, 'newest'])] }
    [
      Bundle.new(report, held_gems),
      Rubies.new(report, Document.keys(holds, ['ruby_lines'])),
      Nginx.new(report),
      Images.new(report),
      Actions.new(report),
      Tools.new(report)
    ]
  end
end

exit(Outdated.run) if $PROGRAM_NAME == __FILE__
