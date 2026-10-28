# typed: strict
# frozen_string_literal: true

require 'json'
require 'net/http'
require 'sorbet-runtime'
require 'uri'

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
      fetch(Net::HTTP::Get, url, headers)
    end

    # HEADs +url+; returns the successful or 401 response, raises on any other.
    # @param url [String]
    # @param headers [Hash{Symbol => String}]
    # @return [Net::HTTPResponse]
    sig { params(url: String, headers: T::Hash[Symbol, String]).returns(Net::HTTPResponse) }
    def self.head(url, headers = {})
      fetch(Net::HTTP::Head, url, headers)
    end

    # GETs and parses the JSON document at +url+ (read it with Document).
    # @param url [String]
    # @param headers [Hash{Symbol => String}]
    # @return [Object]
    sig { params(url: String, headers: T::Hash[Symbol, String]).returns(Object) }
    def self.json(url, headers = {})
      JSON.parse(get(url, headers).body.to_s)
    end

    sig do
      params(method: T.any(T.class_of(Net::HTTP::Get), T.class_of(Net::HTTP::Head)), url: String,
             headers: T::Hash[Symbol, String]).returns(Net::HTTPResponse)
    end
    private_class_method def self.fetch(method, url, headers)
      MAX_REDIRECTS.times do
        response = perform(method.new(URI(url), headers))
        return checked(response, url) unless response.is_a?(Net::HTTPRedirection)

        url = String(URI.join(url, response.fetch('location')))
      end
      raise "#{url}: more than #{MAX_REDIRECTS} redirects"
    end

    sig { params(request: T.any(Net::HTTP::Get, Net::HTTP::Head)).returns(Net::HTTPResponse) }
    private_class_method def self.perform(request)
      uri = URI(request.uri.to_s)
      Net::HTTP.start(uri.host, uri.port, use_ssl: true) { |http| http.request(request) }
    end

    sig { params(response: Net::HTTPResponse, url: String).returns(Net::HTTPResponse) }
    private_class_method def self.checked(response, url)
      return response if response.is_a?(Net::HTTPSuccess) || response.is_a?(Net::HTTPUnauthorized)

      raise "#{url}: #{response.code} #{response.message}"
    end
  end
end
