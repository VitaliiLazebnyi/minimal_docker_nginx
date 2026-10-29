# typed: strict
# frozen_string_literal: true

require 'open3'
require 'sorbet-runtime'

module Outdated
  # The tags of a remote git repository.
  module GitTags
    extend T::Sig

    # Tag name => commit; annotated tags are peeled to the commit they point to.
    # @param url [String] the repository URL
    # @return [Hash{String => String}]
    sig { params(url: String).returns(T::Hash[String, String]) }
    def self.of(url)
      output, status = Open3.capture2('git', 'ls-remote', '--tags', url)
      raise "git ls-remote #{url} failed" unless status.success?

      peel(output.lines.map(&:split))
    end

    # Maps `git ls-remote` lines ([commit, ref]) to tag => commit, preferring the peeled `tag^{}` lines.
    # @param refs [Array<Array<String>>]
    # @return [Hash{String => String}]
    sig { params(refs: T::Array[T::Array[String]]).returns(T::Hash[String, String]) }
    def self.peel(refs)
      refs.each_with_object({}) do |(commit, ref), tags|
        name = ref.to_s.delete_prefix('refs/tags/')
        tag = name.delete_suffix('^{}')
        tags[tag] = commit.to_s if tag != name || !tags.key?(tag)
      end
    end
  end
end
