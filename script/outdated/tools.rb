# typed: strong
# frozen_string_literal: true

# Copyright (c) 2026 Vitalii Lazebnyi

require 'sorbet-runtime'
require_relative 'document'
require_relative 'git_tags'
require_relative 'http'
require_relative 'report'

module Outdated
  # The linters: the Python tools (tools/requirements.txt, with their dependencies) and the standalone release
  # binaries (tools/binaries.json).
  class Tools
    extend T::Sig

    # A release tag: "v" and a version number.
    RELEASE = /\Av\d+(?:\.\d+)*\z/
    # A pinned package of tools/requirements.txt.
    REQUIREMENT = /^(?<name>[\w.-]+)==(?<version>\S+)/
    private_constant :RELEASE, :REQUIREMENT

    # The newest release of a GitHub repository, from its "v"-prefixed tags.
    # @param repository [String] e.g. "mvdan/sh"
    # @return [String]
    sig { params(repository: String).returns(String) }
    def self.newest_release(repository)
      Outdated.newest(
        GitTags.of("https://github.com/#{repository}").keys.grep(RELEASE) do |tag|
          tag.delete_prefix('v')
        end
      )
    end

    # @param report [Report]
    sig { params(report: Report).void }
    def initialize(report)
      @report = report
    end

    # Runs the checks.
    sig { void }
    def check
      check_python
      check_binaries
    end

    private

    # Every package of tools/requirements.txt must be at its newest release on PyPI.
    sig { void }
    def check_python
      Outdated.matches(File.read(File.join(ROOT, 'tools', 'requirements.txt')), REQUIREMENT).each do |match|
        name = Outdated.group(match, 'name')
        newest = Document.string(Http.json("https://pypi.org/pypi/#{name}/json"), %w[info version])
        @report.compare("Python package #{name} (tools/requirements.txt)", Outdated.group(match, 'version'), newest)
      end
    end

    # Every binary of tools/binaries.json must be the newest release of its repository.
    sig { void }
    def check_binaries
      pins = Document.parse(File.read(File.join(ROOT, 'tools', 'binaries.json')))
      Document.entries(pins).each { |tool| check_binary(pins, tool) }
    end

    # Reports the binary +tool+ unless it is the newest release of its repository.
    # @param pins [Object] the parsed tools/binaries.json
    # @param tool [String]
    sig { params(pins: Object, tool: String).void }
    def check_binary(pins, tool)
      newest = Tools.newest_release(Document.string(pins, [tool, 'repository']))
      @report.compare("#{tool} (tools/binaries.json)", Document.string(pins, [tool, 'version']), newest)
    end
  end
end
