# typed: strong
# frozen_string_literal: true

# Copyright (c) 2026 Vitalii Lazebnyi

require 'net/http'
require 'sorbet-runtime'
require 'uri'

require_relative 'document'
require_relative 'error'

module Outdated
  # HTTPS requests (following redirects) and JSON documents.
  module Http
    extend T::Sig

    # Redirects followed before a request fails.
    MAX_REDIRECTS = 5
    public_constant :MAX_REDIRECTS

    # GETs +url+; returns the successful or 401 response, raises on any other.
    # @param url [String]
    # @param headers [Hash{Symbol => String}]
    # @return [Net::HTTPResponse]
    # @raise [Error] on any other response
    sig { params(url: String, headers: T::Hash[Symbol, String]).returns(Net::HTTPResponse) }
    def self.get(url, headers = {})
      checked(fetch(Net::HTTP::Get, URI(url), headers), url)
    end

    # GETs +url+ like ::get, but returns nil when the server answers 404 Not Found.
    # @param url [String]
    # @return [Net::HTTPResponse, nil]
    # @raise [Error] on any other unsuccessful response
    sig { params(url: String).returns(T.nilable(Net::HTTPResponse)) }
    def self.find(url)
      case (response = fetch(Net::HTTP::Get, URI(url), {}))
      when Net::HTTPNotFound then nil
      else checked(response, url)
      end
    end

    # HEADs +url+; returns the successful or 401 response, raises on any other.
    # @param url [String]
    # @param headers [Hash{Symbol => String}]
    # @return [Net::HTTPResponse]
    # @raise [Error] on any other response
    sig { params(url: String, headers: T::Hash[Symbol, String]).returns(Net::HTTPResponse) }
    def self.head(url, headers = {})
      checked(fetch(Net::HTTP::Head, URI(url), headers), url)
    end

    # The body of +response+ ("" when it has none).
    # @param response [Net::HTTPResponse]
    # @return [String]
    sig { params(response: Net::HTTPResponse).returns(String) }
    def self.body(response)
      response.body.to_s
    end

    # The JSON document of +response+ (read it with Document).
    # @param response [Net::HTTPResponse]
    # @return [Object]
    sig { params(response: Net::HTTPResponse).returns(Object) }
    def self.document(response)
      Document.parse(body(response))
    end

    # GETs and parses the JSON document at +url+ (read it with Document).
    # @param url [String]
    # @param headers [Hash{Symbol => String}]
    # @return [Object]
    sig { params(url: String, headers: T::Hash[Symbol, String]).returns(Object) }
    def self.json(url, headers = {})
      document(get(url, headers))
    end

    # Performs the request, following up to MAX_REDIRECTS redirects.
    # @param method [Class] Net::HTTP::Get or Net::HTTP::Head
    # @param uri [URI::Generic]
    # @param headers [Hash{Symbol => String}]
    # @return [Net::HTTPResponse]
    # @raise [Error] when the server redirects once more
    sig do
      params(
        method: T.any(T.class_of(Net::HTTP::Get), T.class_of(Net::HTTP::Head)),
        uri: URI::Generic,
        headers: T::Hash[Symbol, String]
      ).returns(Net::HTTPResponse)
    end
    private_class_method def self.fetch(method, uri, headers)
      (MAX_REDIRECTS + 1).times do
        response = perform(method.new(uri, headers), uri)
        return response unless response.is_a?(Net::HTTPRedirection)

        uri = uri.merge(T.let(response.fetch('location'), String))
      end
      raise(Error, "#{uri}: more than #{MAX_REDIRECTS} redirects")
    end

    # Performs one request over TLS.
    # @param request [Net::HTTPGenericRequest]
    # @param uri [URI::Generic] the URI of the request
    # @return [Net::HTTPResponse]
    sig { params(request: Net::HTTPGenericRequest, uri: URI::Generic).returns(Net::HTTPResponse) }
    private_class_method def self.perform(request, uri)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      T.let(http.request(request), Net::HTTPResponse)
    end

    # +response+ when it is successful or a 401 Unauthorized.
    # @param response [Net::HTTPResponse]
    # @param url [String]
    # @return [Net::HTTPResponse]
    # @raise [Error] on any other response
    sig { params(response: Net::HTTPResponse, url: String).returns(Net::HTTPResponse) }
    private_class_method def self.checked(response, url)
      case response
      when Net::HTTPSuccess, Net::HTTPUnauthorized then response
      else raise(Error, "#{url}: #{response.code} #{response.message}")
      end
    end
  end
end
