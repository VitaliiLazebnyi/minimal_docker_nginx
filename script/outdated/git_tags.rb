# typed: strong
# frozen_string_literal: true

# Copyright (c) 2026 Vitalii Lazebnyi

require 'open3'
require 'sorbet-runtime'

require_relative 'error'

module Outdated
  # The tags of a remote git repository.
  module GitTags
    extend T::Sig

    # Tag name => commit; annotated tags are peeled to the commit they point to.
    # @param url [String] the repository URL
    # @return [Hash{String => String}]
    # @raise [Error] when the repository cannot be listed
    sig { params(url: String).returns(T::Hash[String, String]) }
    def self.of(url)
      output, status = Open3.capture2('git', 'ls-remote', '--tags', url)
      raise(Error, "git ls-remote #{url} failed") unless status.success?

      peel(output.lines.map(&:split))
    end

    # Maps `git ls-remote` lines ([commit, ref]) to tag => commit, preferring the peeled `tag^{}` lines.
    # @param refs [Array<Array<String>>]
    # @return [Hash{String => String}]
    sig { params(refs: T::Array[T::Array[String]]).returns(T::Hash[String, String]) }
    def self.peel(refs)
      refs.each_with_object({}) do |fields, tags|
        ref = fields.fetch(1).delete_prefix('refs/tags/')
        tag = ref.delete_suffix('^{}')
        tags[tag] = fields.fetch(0) if ref.end_with?('^{}') || !tags.key?(tag)
      end
    end
  end
end
