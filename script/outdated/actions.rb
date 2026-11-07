# typed: strict
# frozen_string_literal: true

require 'sorbet-runtime'
require_relative 'git_tags'
require_relative 'report'

module Outdated
  # Every GitHub Action is pinned to the commit of its newest release tag, named in a trailing comment.
  class Actions
    extend T::Sig

    REFERENCE = %r{uses: +(?<repository>[\w.-]+/[\w.-]+)[\w./-]*@(?<commit>\h{40}) +# +(?<tag>v[\d.]+)}
    RELEASE_TAG = /\Av\d+(\.\d+)*\z/
    private_constant :REFERENCE, :RELEASE_TAG

    # @param report [Report]
    sig { params(report: Report).void }
    def initialize(report)
      @report = report
    end

    # Runs the checks (once per distinct action reference).
    sig { void }
    def check
      references = PINNING_FILES.flat_map { |path| File.read(path).scan(REFERENCE) }
      references.uniq.each { |repository, commit, tag| check_action(repository.to_s, commit.to_s, tag.to_s) }
    end

    private

    sig { params(repository: String, commit: String, tag: String).void }
    def check_action(repository, commit, tag)
      tags = GitTags.of("https://github.com/#{repository}")
      releases = tags.keys.grep(RELEASE_TAG).map { |name| name.delete_prefix('v') }
      @report.compare("action #{repository} tag", tag, "v#{Outdated.newest(releases)}")
      @report.compare("action #{repository}@#{tag} commit", commit, tags.fetch(tag, 'no such tag'))
    end
  end
end
