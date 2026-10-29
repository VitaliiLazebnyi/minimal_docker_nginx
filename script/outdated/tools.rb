# typed: strict
# frozen_string_literal: true

require 'json'
require 'sorbet-runtime'
require_relative 'document'
require_relative 'http'
require_relative 'report'

module Outdated
  # The Python tools (tools/requirements.txt, with their dependencies).
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
      File.read(File.join(ROOT, 'tools', 'requirements.txt')).scan(/^([\w.-]+)==(\S+)/).each do |name, pinned|
        newest = Document.string(Http.json("https://pypi.org/pypi/#{name}/json"), %w[info version])
        @report.compare("Python package #{name} (tools/requirements.txt)", pinned.to_s, newest)
      end
    end
  end
end
