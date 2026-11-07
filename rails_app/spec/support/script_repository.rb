# typed: strict
# frozen_string_literal: true

# Copyright (c) 2026 Vitalii Lazebnyi

require 'fileutils'
require 'sorbet-runtime'

# A repository for the specs of the scripts of script/: the files an example needs, in a directory that the
# example's Outdated::ROOT, Outdated::APP and Outdated::PINNING_FILES point to.
module ScriptRepository
  extend T::Sig

  # Writes +files+ (each a path relative to +root+ and its content) and points the paths of Outdated at +root+ for
  # +example+.
  # @param example [RSpec::Core::ExampleGroup] the running example
  # @param root [String] the directory of the repository
  # @param files [Array<Array(String, String)>]
  sig { params(example: RSpec::Core::ExampleGroup, root: String, files: [String, String]).void }
  def self.install(example, root, *files)
    files.each do |path, content|
      file = File.join(root, path)
      FileUtils.mkdir_p(File.dirname(file))
      File.write(file, content)
    end
    example.stub_const('Outdated::ROOT', root)
    example.stub_const('Outdated::APP', File.join(root, 'rails_app'))
    example.stub_const('Outdated::PINNING_FILES', pinning_files(root))
  end

  # The Dockerfile and the workflows of the repository at +root+.
  # @param root [String]
  # @return [Array<String>]
  sig { params(root: String).returns(T::Array[String]) }
  def self.pinning_files(root)
    [File.join(root, 'Dockerfile'), *Dir[File.join(root, '.github', 'workflows', '*.yml')]]
  end
end

# A check of script/outdated.rb for the specs of Outdated.run: it reports a problem (silently) when it fails.
class CheckStub
  extend T::Sig

  # @param example [RSpec::Core::ExampleGroup] the running example
  # @param report [Outdated::Report] the report the check reports to
  # @param failing [Boolean] whether the check fails
  sig { params(example: RSpec::Core::ExampleGroup, report: Outdated::Report, failing: T::Boolean).void }
  def initialize(example, report, failing)
    @report = report
    @failing = failing
    example.allow(report).to(example.receive(:warn))
  end

  # Runs the check.
  sig { void }
  def check
    @report.problem('check failed') if @failing
  end
end

# Changes of the `dependency-changes` output of dependency-review-action, for the specs of script/scorecards.rb.
module DependencyChanges
  extend T::Sig

  # The Scorecard API URL of the repository of ::added.
  SCORECARD = 'https://api.securityscorecards.dev/projects/github.com/o/a'
  # The deps.dev URL of the version of ::npm.
  NPM_VERSION = 'https://api.deps.dev/v3/systems/npm/packages/%40s%2Fp/versions/1'
  public_constant :SCORECARD, :NPM_VERSION

  # A gem added with its source repository, github.com/o/a.
  # @return [String] the change, as JSON
  sig { returns(String) }
  def self.added
    '{"change_type": "added", "ecosystem": "rubygems", "name": "a", "version": "1", ' \
      '"source_repository_url": "https://github.com/o/a"}'
  end

  # An npm package added without a source repository, whose name needs escaping in a URL.
  # @return [String] the changes, as JSON
  sig { returns(String) }
  def self.npm
    '[{"change_type": "added", "ecosystem": "npm", "name": "@s/p", "version": "1", "source_repository_url": null}]'
  end
end
