#!/usr/bin/env ruby
# typed: strict
# frozen_string_literal: true

# Fails when a pull request adds a dependency whose OpenSSF Scorecard (https://scorecard.dev) is below THRESHOLD and
# that is not explicitly allowed, with its reason, in script/scorecard_allowances.yml. Also fails when an allowance is
# no longer needed (the package is gone from every lockfile, or its score reached the threshold).
#
# It replaces the warning-only Scorecard report of actions/dependency-review-action, which has no per-package
# allowance: the Dependency review job passes the action's `dependency-changes` output as DEPENDENCY_CHANGES.
# Scores are looked up the way the action does: the repository URL of the change (deps.dev when it has none), then
# api.securityscorecards.dev.

require 'json'
require 'sorbet-runtime'
require 'uri'
require 'yaml'

require_relative 'outdated/document'
require_relative 'outdated/http'
require_relative 'outdated/report'

# The OpenSSF Scorecard check of added dependencies; see the header of this file.
module Scorecards
  extend T::Sig

  # The score below which a dependency needs an allowance (the default of actions/dependency-review-action).
  THRESHOLD = 3.0
  # Lockfiles in which an allowed package must still appear.
  LOCKFILES = %w[rails_app/Gemfile.lock tools/requirements.txt].freeze
  public_constant :THRESHOLD, :LOCKFILES

  # The allowances of script/scorecard_allowances.yml: "ecosystem/name" => reason.
  class Allowances
    extend T::Sig

    # @return [Allowances] the allowances of script/scorecard_allowances.yml
    sig { returns(Allowances) }
    def self.load
      new(YAML.safe_load_file(File.join(Outdated::ROOT, 'script', 'scorecard_allowances.yml')))
    end

    # @param document [Object] the parsed allowance file
    sig { params(document: Object).void }
    def initialize(document)
      @document = document
    end

    # Reports a dependency below the threshold: allowed (with its reason) or a problem.
    # @param report [Outdated::Report]
    # @param key [String] "ecosystem/name"
    # @param label [String] what is reported about the dependency
    sig { params(report: Outdated::Report, key: String, label: String).void }
    def below(report, key, label)
      if allowed?(key)
        report.info("#{label}, allowed: #{Outdated::Document.string(@document, [key, 'reason'])}")
      else
        report.problem("#{label} is below #{THRESHOLD} and not in script/scorecard_allowances.yml")
      end
    end

    # Reports an allowance of a dependency that reached the threshold.
    # @param report [Outdated::Report]
    # @param key [String] "ecosystem/name"
    sig { params(report: Outdated::Report, key: String).void }
    def reached(report, key)
      report.problem("stale allowance: #{key} now scores #{THRESHOLD} or more") if allowed?(key)
    end

    # Reports every allowance whose package is in no lockfile any more.
    # @param report [Outdated::Report]
    sig { params(report: Outdated::Report).void }
    def check_locked(report)
      locked = LOCKFILES.map { |path| File.read(File.join(Outdated::ROOT, path)) }.join("\n")
      Outdated::Document.keys(@document, []).each do |key|
        name = Regexp.escape(key.split('/', 2).last.to_s)
        report.problem("stale allowance: #{key} is in no lockfile") unless locked.match?(/^\s*#{name}[ (=]/)
      end
    end

    private

    sig { params(key: String).returns(T::Boolean) }
    def allowed?(key)
      Outdated::Document.key?(@document, [key])
    end
  end

  # An added dependency: its ecosystem, name, version and source repository.
  class Dependency < T::Struct
    extend T::Sig

    const :ecosystem, String
    const :name, String
    const :version, String
    const :repository, String

    # A change of the `dependency-changes` output of dependency-review-action.
    # @param change [Object]
    # @return [Dependency]
    sig { params(change: Object).returns(Dependency) }
    def self.from(change)
      repository = Outdated::Document.at(change, ['source_repository_url'])
      field = ->(key) { Outdated::Document.string(change, [key]) }
      new(ecosystem: field.call('ecosystem'), name: field.call('name'), version: field.call('version'),
          repository: repository.is_a?(String) ? repository : '')
    end

    # "ecosystem/name", the key of script/scorecard_allowances.yml.
    # @return [String]
    sig { returns(String) }
    def key
      "#{ecosystem}/#{name}"
    end

    # Reports the Scorecard of the dependency.
    # @param report [Outdated::Report]
    # @param allowances [Allowances]
    sig { params(report: Outdated::Report, allowances: Allowances).void }
    def check(report, allowances)
      found, score = scorecard
      label = "#{key} #{version} (#{found || 'no repository'}): Scorecard #{score || 'none'}"
      return allowances.below(report, key, label) if score && score < THRESHOLD

      report.info(label)
      allowances.reached(report, key) if score
    end

    private

    # The repository whose Scorecard applies and its score (nil when there is none).
    sig { returns([T.nilable(String), T.nilable(Float)]) }
    def scorecard
      found = project
      [found, found && Scorecards.score(found)]
    end

    # The repository whose Scorecard applies: the change's own, else the one deps.dev relates to the version.
    sig { returns(T.nilable(String)) }
    def project
      return repository.delete_prefix('https://') unless repository.empty?

      path = [ecosystem, 'packages', name, 'versions', version].map { |part| URI.encode_uri_component(part) }
      response = Outdated::Http.find("https://api.deps.dev/v3/systems/#{path.join('/')}")
      Scorecards.first_project(JSON.parse(response.body.to_s)) if response
    end
  end

  # The first repository of a deps.dev version document, if any.
  # @param document [Object] a parsed deps.dev version document
  # @return [String, nil]
  sig { params(document: Object).returns(T.nilable(String)) }
  def self.first_project(document)
    projects = Outdated::Document.key?(document,
                                       ['relatedProjects']) && Outdated::Document.at(document, ['relatedProjects'])
    first = projects.is_a?(Array) ? projects.first : nil
    Outdated::Document.string(first, %w[projectKey id]) if first
  end

  # The Scorecard score of a repository, or nil when Scorecard has not scored it.
  # @param project [String] e.g. "github.com/owner/repo"
  # @return [Float, nil]
  sig { params(project: String).returns(T.nilable(Float)) }
  def self.score(project)
    response = Outdated::Http.find("https://api.securityscorecards.dev/projects/#{project}")
    value = response && Outdated::Document.at(JSON.parse(response.body.to_s), ['score'])
    Float(value) if value.is_a?(Numeric)
  end

  # The dependencies added by the pull request (the `dependency-changes` output of dependency-review-action).
  # @param json [String]
  # @return [Array<Dependency>]
  sig { params(json: String).returns(T::Array[Dependency]) }
  def self.added(json)
    changes = JSON.parse(json)
    return [] unless changes.is_a?(Array)

    changes.filter_map do |change|
      Dependency.from(change) if Outdated::Document.string(change, ['change_type']) == 'added'
    end
  end

  # Runs the check and returns the process exit status.
  # @return [Integer]
  sig { returns(Integer) }
  def self.run
    report = Outdated::Report.new('SCORECARD')
    check(report, Allowances.load, ENV.fetch('DEPENDENCY_CHANGES', '[]'))
    report.status
  end

  # Checks every dependency added by +changes+, then every allowance.
  # @param report [Outdated::Report]
  # @param allowances [Allowances]
  # @param changes [String] the `dependency-changes` output of dependency-review-action
  sig { params(report: Outdated::Report, allowances: Allowances, changes: String).void }
  def self.check(report, allowances, changes)
    added(changes).uniq(&:key).each { |dependency| dependency.check(report, allowances) }
    allowances.check_locked(report)
  end
end

exit(Scorecards.run) if $PROGRAM_NAME == __FILE__
