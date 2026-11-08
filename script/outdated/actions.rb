# typed: strong
# frozen_string_literal: true

# Copyright (c) 2026 Vitalii Lazebnyi

require 'sorbet-runtime'
require_relative 'git_tags'
require_relative 'report'

module Outdated
  # Every GitHub Action is pinned to the commit of its newest release tag, named in a trailing comment.
  class Actions
    extend T::Sig

    # A pinned action: `uses: owner/repository[/path]@commit # tag`.
    REFERENCE = %r{uses: +(?<repository>[\w.-]+/[\w.-]+)[\w./-]*@(?<commit>\h{40}) +# +(?<tag>v[\d.]+)}
    # A release tag: "v" and a version number.
    RELEASE_TAG = /\Av\d+(\.\d+)*\z/
    private_constant :REFERENCE, :RELEASE_TAG

    # The action references of the pinning files: [repository, commit, tag].
    # @return [Array<Array(String, String, String)>]
    sig { returns(T::Array[[String, String, String]]) }
    def self.references
      matches = PINNING_FILES.flat_map { |path| Outdated.matches(File.read(path), REFERENCE) }
      matches.map { |match| reference(match) }
    end

    # The repository, commit and tag of a match of REFERENCE.
    # @param match [MatchData]
    # @return [Array(String, String, String)]
    sig { params(match: MatchData).returns([String, String, String]) }
    def self.reference(match)
      [Outdated.group(match, 'repository'), Outdated.group(match, 'commit'), Outdated.group(match, 'tag')]
    end

    # @param report [Report]
    sig { params(report: Report).void }
    def initialize(report)
      @report = report
    end

    # Runs the checks (once per distinct action reference).
    sig { void }
    def check
      Actions.references.uniq.each { |repository, commit, tag| check_action(repository, commit, tag) }
    end

    private

    # Reports the tag unless it is the newest release, and the commit unless the tag points to it.
    # @param repository [String]
    # @param commit [String]
    # @param tag [String]
    sig { params(repository: String, commit: String, tag: String).void }
    def check_action(repository, commit, tag)
      tags = GitTags.of("https://github.com/#{repository}")
      releases = tags.keys.grep(RELEASE_TAG) { |name| name.delete_prefix('v') }
      @report.compare("action #{repository} tag", tag, "v#{Outdated.newest(releases)}")
      @report.compare("action #{repository}@#{tag} commit", commit, tags.fetch(tag, 'no such tag'))
    end
  end
end
