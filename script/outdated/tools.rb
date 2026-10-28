# typed: strict
# frozen_string_literal: true

require 'json'
require 'sorbet-runtime'
require_relative 'document'
require_relative 'http'
require_relative 'report'

module Outdated
  # The Python tools (tools/requirements.txt, with their dependencies) and the npm tools (package.json).
  class Tools
    extend T::Sig

    # @param report [Report]
    sig { params(report: Report).void }
    def initialize(report)
      @report = report
    end

    # Runs the checks.
    sig { void }
    def check
      check_python
      check_npm
    end

    private

    sig { void }
    def check_python
      File.read(File.join(ROOT, 'tools', 'requirements.txt')).scan(/^([\w.-]+)==(\S+)/).each do |name, pinned|
        newest = Document.string(Http.json("https://pypi.org/pypi/#{name}/json"), %w[info version])
        @report.compare("Python package #{name} (tools/requirements.txt)", pinned.to_s, newest)
      end
    end

    # The npm tools (devDependencies) and the versions they are forced to (overrides) must be the newest.
    sig { void }
    def check_npm
      package = JSON.parse(File.read(File.join(ROOT, 'package.json')))
      %w[devDependencies overrides].each { |section| check_npm_section(package, section) }
    end

    sig { params(package: Object, section: String).void }
    def check_npm_section(package, section)
      Document.keys(package, [section]).each { |name| check_npm_package(package, section, name) }
    end

    sig { params(package: Object, section: String, name: String).void }
    def check_npm_package(package, section, name)
      pinned = Document.string(package, [section, name])
      newest = Document.string(Http.json("https://registry.npmjs.org/#{name}/latest"), ['version'])
      @report.compare("npm package #{name} (package.json #{section})", pinned, newest)
    end
  end
end
