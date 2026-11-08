# typed: strong
# frozen_string_literal: true

# Copyright (c) 2026 Vitalii Lazebnyi

require 'sorbet-runtime'
require_relative 'git_tags'
require_relative 'report'

module Outdated
  # The image must build the newest nginx release (Dockerfile ARG NGINX_VERSION).
  class Nginx
    extend T::Sig

    # A release tag of nginx: "release-" and the version.
    RELEASE = /\Arelease-\d+\.\d+\.\d+\z/
    private_constant :RELEASE

    # @param report [Report]
    sig { params(report: Report).void }
    def initialize(report)
      @report = report
    end

    # Runs the check.
    sig { void }
    def check
      tags = GitTags.of('https://github.com/nginx/nginx').keys
      releases = tags.grep(RELEASE) { |tag| tag.delete_prefix('release-') }
      newest = Outdated.newest(releases)
      @report.compare('nginx (Dockerfile ARG NGINX_VERSION)', Outdated.dockerfile_arg('NGINX_VERSION'), newest)
    end
  end
end
