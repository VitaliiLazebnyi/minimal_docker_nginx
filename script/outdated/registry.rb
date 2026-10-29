# typed: strict
# frozen_string_literal: true

require 'sorbet-runtime'
require 'uri'
require_relative 'document'
require_relative 'http'

module Outdated
  # Anonymous, read-only access to an OCI/Docker registry (tags and manifest digests).
  class Registry
    extend T::Sig

    DOCKER_HUB = 'registry-1.docker.io'
    MANIFEST_TYPES = T.let(
      %w[
        application/vnd.oci.image.index.v1+json
        application/vnd.docker.distribution.manifest.list.v2+json
        application/vnd.oci.image.manifest.v1+json
        application/vnd.docker.distribution.manifest.v2+json
      ].join(', '),
      String
    )
    private_constant :DOCKER_HUB, :MANIFEST_TYPES

    # The registry of an image name: Docker Hub unless the first path component is a host.
    # @param name [String] e.g. "ruby", "hadolint/hadolint" or "gcr.io/project/image"
    # @return [Registry]
    sig { params(name: String).returns(Registry) }
    def self.for(name)
      first, *path = name.split('/')
      host = first.to_s
      return new(host, path.join('/')) if host.include?('.')

      new(DOCKER_HUB, path.empty? ? "library/#{name}" : name)
    end

    # The URL of the next page named by a `Link` response header, if any.
    # @param url [String] the URL of the current page
    # @param link [String] the `Link` header
    # @return [String, nil]
    sig { params(url: String, link: String).returns(T.nilable(String)) }
    def self.next_page(url, link)
      path = link[/<([^>]+)>;\s*rel="next"/, 1]
      String(URI.join(url, path)) if path
    end

    # @param host [String] the registry host
    # @param repository [String] the repository path on that host
    sig { params(host: String, repository: String).void }
    def initialize(host, repository)
      @host = host
      @repository = repository
      @authorization = T.let(nil, T.nilable(T::Hash[Symbol, String]))
    end

    # Every tag of the repository, following the pagination of the registry.
    # @param url [String] the page to start from
    # @return [Array<String>]
    sig { params(url: String).returns(T::Array[String]) }
    def tags(url = "https://#{@host}/v2/#{@repository}/tags/list?n=1000")
      response = Http.get(url, authorization)
      page = Document.strings(JSON.parse(response.body.to_s), ['tags'])
      next_page = Registry.next_page(url, response['link'].to_s)
      next_page ? page + tags(next_page) : page
    end

    # The digest the tag currently points to.
    # @param tag [String]
    # @return [String] e.g. "sha256:0123..."
    sig { params(tag: String).returns(String) }
    def digest(tag)
      url = "https://#{@host}/v2/#{@repository}/manifests/#{tag}"
      Http.head(url, authorization.merge(Accept: MANIFEST_TYPES)).fetch('docker-content-digest', '')
    end

    private

    # The Authorization header for this repository: an anonymous pull token when the registry asks for one.
    sig { returns(T::Hash[Symbol, String]) }
    def authorization
      @authorization ||= begin
        response = Http.get("https://#{@host}/v2/")
        response.is_a?(Net::HTTPUnauthorized) ? { Authorization: "Bearer #{token(response)}" } : {}
      end
    end

    sig { params(response: Net::HTTPResponse).returns(String) }
    def token(response)
      challenge = Challenge.new(response.fetch('www-authenticate', ''))
      body = Http.json(challenge.token_url(@host, @repository))
      Document.string(body, [Document.key?(body, ['token']) ? 'token' : 'access_token'])
    end

    # A `WWW-Authenticate: Bearer realm="...",service="..."` challenge.
    class Challenge
      extend T::Sig

      # @param header [String] the WWW-Authenticate header
      sig { params(header: String).void }
      def initialize(header)
        @fields = T.let({}, T::Hash[String, String])
        header.scan(/(\w+)="([^"]*)"/) { @fields[Regexp.last_match(1).to_s] = Regexp.last_match(2).to_s }
      end

      # The URL that issues a pull token for +repository+.
      # @param host [String] the registry host (the service when the challenge names none)
      # @param repository [String]
      # @return [String]
      sig { params(host: String, repository: String).returns(String) }
      def token_url(host, repository)
        query = URI.encode_www_form(service: @fields.fetch('service', host), scope: "repository:#{repository}:pull")
        "#{@fields.fetch('realm')}?#{query}"
      end
    end
  end
end
