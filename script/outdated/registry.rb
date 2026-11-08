# typed: strong
# frozen_string_literal: true

# Copyright (c) 2026 Vitalii Lazebnyi

require 'sorbet-runtime'
require 'uri'
require_relative 'document'
require_relative 'http'

module Outdated
  # Anonymous, read-only access to an OCI/Docker registry (tags and manifest digests).
  class Registry
    extend T::Sig

    # The registry of the image names without a host.
    DOCKER_HUB = 'registry-1.docker.io'
    # The Accept header of a manifest request: every manifest and index type, so the digest is the one the tag
    # points to.
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
      host, _, path = name.partition('/')
      return new(host, path) if host.include?('.')

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
      @token = T.let(token, String)
    end

    # Every tag of the repository, following the pagination of the registry.
    # @param url [String] the page to start from
    # @return [Array<String>]
    sig { params(url: String).returns(T::Array[String]) }
    def tags(url = "https://#{@host}/v2/#{@repository}/tags/list?n=1000")
      response = Http.get(url, authorization)
      page = Document.strings(Http.document(response), 'tags')
      next_page = Registry.next_page(url, T.let(response.fetch('link', ''), String))
      next_page ? page + tags(next_page) : page
    end

    # The digest the tag currently points to ("" when the registry names none).
    # @param tag [String]
    # @return [String] e.g. "sha256:0123..."
    sig { params(tag: String).returns(String) }
    def digest(tag)
      url = "https://#{@host}/v2/#{@repository}/manifests/#{tag}"
      T.let(Http.head(url, authorization.merge(Accept: MANIFEST_TYPES)).fetch('docker-content-digest', ''), String)
    end

    private

    # The Authorization header of the requests for this repository: the anonymous pull token, if the registry
    # asks for one.
    # @return [Hash{Symbol => String}]
    sig { returns(T::Hash[Symbol, String]) }
    def authorization
      @token.empty? ? {} : { Authorization: "Bearer #{@token}" }
    end

    # An anonymous pull token for this repository when the registry asks for one (it answers 401 Unauthorized),
    # else "".
    # @return [String]
    sig { returns(String) }
    def token
      case (response = Http.get("https://#{@host}/v2/"))
      when Net::HTTPUnauthorized then pull_token(response)
      else ''
      end
    end

    # An anonymous pull token for this repository, from the token service the challenge of +response+ names.
    # @param response [Net::HTTPResponse] the 401 Unauthorized response
    # @return [String]
    sig { params(response: Net::HTTPResponse).returns(String) }
    def pull_token(response)
      challenge = Challenge.new(T.let(response.fetch('www-authenticate'), String))
      body = Http.json(challenge.token_url(@host, @repository))
      Document.string(body, [Document.key?(body, 'token') ? 'token' : 'access_token'])
    end

    # A `WWW-Authenticate: Bearer realm="...",service="..."` challenge.
    class Challenge
      extend T::Sig

      # @param header [String] the WWW-Authenticate header
      sig { params(header: String).void }
      def initialize(header)
        @header = header
      end

      # The URL that issues a pull token for +repository+.
      # @param host [String] the registry host (the service when the challenge names none)
      # @param repository [String]
      # @return [String]
      sig { params(host: String, repository: String).returns(String) }
      def token_url(host, repository)
        query = URI.encode_www_form(service: fields.fetch('service', host), scope: "repository:#{repository}:pull")
        "#{fields.fetch('realm')}?#{query}"
      end

      private

      # The fields of the challenge: name => value.
      # @return [Hash{String => String}]
      sig { returns(T::Hash[String, String]) }
      def fields
        @header.delete_prefix('Bearer ').split(/,\s*/).to_h do |field|
          name, _, value = field.partition('=')
          [name, value.delete_prefix('"').delete_suffix('"')]
        end
      end
    end
  end
end
