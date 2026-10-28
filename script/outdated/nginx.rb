# typed: strict
# frozen_string_literal: true

require 'sorbet-runtime'
require_relative 'git_tags'
require_relative 'report'

module Outdated
  # The image must build the newest nginx release (Dockerfile ARG NGINX_VERSION).
  class Nginx
    extend T::Sig

    # @param report [Report]
    sig { params(report: Report).void }
    def initialize(report)
      @report = report
    end

    # Runs the check.
    sig { void }
    def check
      tags = GitTags.of('https://github.com/nginx/nginx').keys
      newest = Outdated.newest(tags.filter_map { |tag| tag[/\Arelease-(\d+\.\d+\.\d+)\z/, 1] })
      built = File.read(File.join(ROOT, 'Dockerfile'))[/^ARG NGINX_VERSION=(\S+)/, 1].to_s
      @report.compare('nginx (Dockerfile ARG NGINX_VERSION)', built, newest)
    end
  end
end
