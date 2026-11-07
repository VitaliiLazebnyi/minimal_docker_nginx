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
    sig { params(url: String, headers: T::Hash[Symbol, String]).returns(Net::HTTPResponse) }
    def self.get(url, headers = {})
      checked(fetch(Net::HTTP::Get, url, headers), url)
    end

    # GETs +url+ like ::get, but returns nil when the server answers 404 Not Found.
    # @param url [String]
    # @return [Net::HTTPResponse, nil]
    sig { params(url: String).returns(T.nilable(Net::HTTPResponse)) }
    def self.find(url)
      response = fetch(Net::HTTP::Get, url, {})
      checked(response, url) unless response.is_a?(Net::HTTPNotFound)
    end

    # HEADs +url+; returns the successful or 401 response, raises on any other.
    # @param url [String]
    # @param headers [Hash{Symbol => String}]
    # @return [Net::HTTPResponse]
    sig { params(url: String, headers: T::Hash[Symbol, String]).returns(Net::HTTPResponse) }
    def self.head(url, headers = {})
      checked(fetch(Net::HTTP::Head, url, headers), url)
    end

    # GETs and parses the JSON document at +url+ (read it with Document).
    # @param url [String]
    # @param headers [Hash{Symbol => String}]
    # @return [Object]
    sig { params(url: String, headers: T::Hash[Symbol, String]).returns(Object) }
    def self.json(url, headers = {})
      Document.parse(get(url, headers).body.to_s)
    end

    sig do
      params(
        method: T.any(T.class_of(Net::HTTP::Get), T.class_of(Net::HTTP::Head)),
        url: String,
        headers: T::Hash[Symbol, String]
      ).returns(Net::HTTPResponse)
    end
    private_class_method def self.fetch(method, url, headers)
      MAX_REDIRECTS.times do
        response = perform(method, URI(url), headers)
        return response unless response.is_a?(Net::HTTPRedirection)

        url = String(T.let(URI.join(url, T.let(response.fetch('location'), String)), URI::Generic))
      end
      raise(Error, "#{url}: more than #{MAX_REDIRECTS} redirects")
    end

    sig do
      params(
        method: T.any(T.class_of(Net::HTTP::Get), T.class_of(Net::HTTP::Head)),
        uri: URI::Generic,
        headers: T::Hash[Symbol, String]
      ).returns(Net::HTTPResponse)
    end
    private_class_method def self.perform(method, uri, headers)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      T.let(http.request(method.new(uri, headers)), Net::HTTPResponse)
    end

    sig { params(response: Net::HTTPResponse, url: String).returns(Net::HTTPResponse) }
    private_class_method def self.checked(response, url)
      return response if response.is_a?(Net::HTTPSuccess) || response.is_a?(Net::HTTPUnauthorized)

      raise(Error, "#{url}: #{response.code} #{response.message}")
    end
  end
end
