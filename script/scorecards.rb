# typed: strong
# frozen_string_literal: true

# Copyright (c) 2026 Vitalii Lazebnyi

# Fails when a pull request adds a dependency whose OpenSSF Scorecard (https://scorecard.dev) is below THRESHOLD and
# that is not explicitly allowed, with its reason, in script/scorecard_allowances.yml. Also fails when an allowance is
# no longer needed (the package is gone from every lockfile, or its score reached the threshold).
#
# It replaces the warning-only Scorecard report of actions/dependency-review-action, which has no per-package
# allowance: the Dependency review job runs `bundle exec rake scorecards` in rails_app/ with the action's
# `dependency-changes` output as DEPENDENCY_CHANGES.
# Scores are looked up the way the action does: the repository URL of the change (deps.dev when it has none), then
# api.securityscorecards.dev.

require 'sorbet-runtime'
require 'uri'

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
      new(Outdated::Document.load(File.join(Outdated::ROOT, 'script', 'scorecard_allowances.yml')))
    end

    # The contents of the lockfiles (LOCKFILES).
    # @return [Array<String>]
    sig { returns(T::Array[String]) }
    def self.lockfiles
      LOCKFILES.map { |path| File.read(File.join(Outdated::ROOT, path)) }
    end

    # Whether a lockfile has the package +key+.
    # @param lockfiles [Array<String>] the contents of the lockfiles
    # @param key [String] "ecosystem/name"
    # @return [Boolean]
    sig { params(lockfiles: T::Array[String], key: String).returns(T::Boolean) }
    def self.locked?(lockfiles, key)
      _, _, name = key.partition('/')
      entry = /^\s*#{Regexp.escape(name)}[ (=]/
      lockfiles.any? { |lockfile| lockfile.match?(entry) }
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
      lockfiles = Allowances.lockfiles
      stale = Outdated::Document.keys(@document, []).reject { |key| Allowances.locked?(lockfiles, key) }
      stale.each { |key| report.problem("stale allowance: #{key} is in no lockfile") }
    end

    private

    # Whether script/scorecard_allowances.yml allows the package +key+.
    # @param key [String] "ecosystem/name"
    # @return [Boolean]
    sig { params(key: String).returns(T::Boolean) }
    def allowed?(key)
      Outdated::Document.key?(@document, key)
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
      new(
        ecosystem: Outdated::Document.string(change, ['ecosystem']),
        name: Outdated::Document.string(change, ['name']),
        version: Outdated::Document.string(change, ['version']),
        repository: Outdated::Document.at(change, ['source_repository_url']).to_s
      )
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
    # @return [Array(String, Float), Array(nil, nil), Array(String, nil)]
    sig { returns([T.nilable(String), T.nilable(Float)]) }
    def scorecard
      found = project
      [found, found && Scorecards.score(found)]
    end

    # The repository whose Scorecard applies: the change's own, else the one deps.dev relates to the version.
    # @return [String, nil]
    sig { returns(T.nilable(String)) }
    def project
      return repository.delete_prefix('https://') unless repository.empty?

      path = [ecosystem, 'packages', name, 'versions', version].map { |part| URI.encode_uri_component(part) }
      response = Outdated::Http.find("https://api.deps.dev/v3/systems/#{path.join('/')}")
      Scorecards.first_project(Outdated::Http.document(response)) if response
    end
  end

  # The first repository of a deps.dev version document, if any.
  # @param document [Object] a parsed deps.dev version document
  # @return [String, nil]
  sig { params(document: Object).returns(T.nilable(String)) }
  def self.first_project(document)
    first = Outdated::Document.list(document, 'relatedProjects').first
    Outdated::Document.string(first, %w[projectKey id]) if first
  end

  # The Scorecard score of a repository, or nil when Scorecard has not scored it.
  # @param project [String] e.g. "github.com/owner/repo"
  # @return [Float, nil]
  sig { params(project: String).returns(T.nilable(Float)) }
  def self.score(project)
    response = Outdated::Http.find("https://api.securityscorecards.dev/projects/#{project}")
    value = response && Outdated::Document.at(Outdated::Http.document(response), ['score'])
    Float(value) if value.is_a?(Numeric)
  end

  # The dependencies added by the pull request (the `dependency-changes` output of dependency-review-action).
  # @param json [String]
  # @return [Array<Dependency>]
  # @raise [ArgumentError] when the document is not a list
  sig { params(json: String).returns(T::Array[Dependency]) }
  def self.added(json)
    case (changes = Outdated::Document.parse(json))
    when Array then additions(changes)
    else raise(ArgumentError, "the dependency changes are not a list: #{changes.inspect}")
    end
  end

  # The dependencies of the changes whose type is "added".
  # @param changes [Array<Object>] the changes of the `dependency-changes` output of dependency-review-action
  # @return [Array<Dependency>]
  sig { params(changes: T::Array[Object]).returns(T::Array[Dependency]) }
  def self.additions(changes)
    added = changes.select { |change| Outdated::Document.string(change, ['change_type']) == 'added' }
    added.map { |change| Dependency.from(change) }
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
