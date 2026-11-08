# typed: strong
# frozen_string_literal: true

# Copyright (c) 2026 Vitalii Lazebnyi

require 'sorbet-runtime'
require_relative '../../lib/tasks/quality_gates'

# Creates a git repository with a commit and two tags, for the specs of the scripts that list the tags of a
# repository.
module GitRepository
  extend T::Sig

  # The identity of the commit and of the annotated tag; signing is off, whatever the user's configuration says.
  GIT = %w[git -c user.name=Spec -c user.email=spec@example.com -c commit.gpgsign=false -c tag.gpgsign=false].freeze
  public_constant :GIT

  # Creates the repository in +directory+: one commit, tagged v1.0 (lightweight) and v1.1 (annotated).
  # @param directory [String]
  # @return [String] the commit
  sig { params(directory: String).returns(String) }
  def self.init(directory)
    git(directory, 'init', '--quiet')
    git(directory, 'commit', '--quiet', '--allow-empty', '--message', 'Initial commit')
    git(directory, 'tag', 'v1.0')
    git(directory, 'tag', '--annotate', 'v1.1', '--message', 'Release 1.1')
    git(directory, 'rev-parse', 'HEAD').strip
  end

  # Runs git in +directory+.
  # @param directory [String]
  # @param arguments [Array<String>]
  # @return [String] the output
  # @raise [ArgumentError] when git fails
  sig { params(directory: String, arguments: String).returns(String) }
  def self.git(directory, *arguments)
    output, status = QualityGates.run([*GIT, '-C', directory, *arguments])
    raise(ArgumentError, "git #{arguments.join(' ')} failed:\n#{output}") unless status&.success?

    output
  end
end
