# typed: strict
# frozen_string_literal: true

# Copyright (c) 2026 Vitalii Lazebnyi

require 'net/http'
require 'sorbet-runtime'
require 'stringio'
require_relative 'fake_https/request'

# Answers the HTTPS requests of the scripts in the specs: every Net::HTTP connection is replaced (#install) by one that
# answers from a table of canned responses, and records the requests it receives.
class FakeHttps
  extend T::Sig

  # Builds a parsed response, the way Net::HTTP reads one from a socket.
  # @param status [String] the status code and reason, e.g. "200 OK"
  # @param body [String]
  # @param headers [Array<Array(String, String)>] the header fields, as name and value
  # @return [Net::HTTPResponse]
  sig { params(status: String, body: String, headers: T::Array[[String, String]]).returns(Net::HTTPResponse) }
  def self.response(status, body: '', headers: [])
    fields = [['Content-Length', body.bytesize.to_s], *headers].map { |name, value| "#{name}: #{value}\r\n" }
    socket = Net::BufferedIO.new(StringIO.new("HTTP/1.1 #{status}\r\n#{fields.join}\r\n#{body}"))
    response = Net::HTTPResponse.read_new(socket)
    response.reading_body(socket, true) { nil }
    response
  end

  # A response with the JSON document +document+ as its body.
  # @param document [String] a JSON document
  # @return [Net::HTTPResponse]
  sig { params(document: String).returns(Net::HTTPResponse) }
  def self.json(document)
    response('200 OK', body: document)
  end

  sig { void }
  def initialize
    @responses = T.let({}, T::Hash[String, Net::HTTPResponse])
    @requests = T.let([], T::Array[Request])
  end

  # The requests received so far, in order.
  sig { returns(T::Array[Request]) }
  attr_reader :requests

  # The last request received.
  # @return [Request]
  sig { returns(Request) }
  def last_request
    requests.fetch(-1)
  end

  # Answers +method+ +url+ with +response+.
  # @param method [String] "GET" or "HEAD"
  # @param url [String]
  # @param response [Net::HTTPResponse]
  # @return [FakeHttps] itself
  sig { params(method: String, url: String, response: Net::HTTPResponse).returns(FakeHttps) }
  def answer(method, url, response)
    @responses["#{method} #{url}"] = response
    self
  end

  # Replaces every Net::HTTP connection that +example+ opens by one that this server answers.
  # @param example [RSpec::Core::ExampleGroup] the running example
  sig { params(example: RSpec::Core::ExampleGroup).void }
  def install(example)
    server = self
    example.allow(Net::HTTP).to(
      example.receive(:new).and_wrap_original do |original, host, port|
        connection = original.call(host, port)
        example.allow(connection).to(example.receive(:request)) do |request|
          server.perform(request, host, port, connection.use_ssl?)
        end
        connection
      end
    )
  end

  # Performs +request+ on the connection to +host+:+port+ that used SSL or not (+ssl+).
  # @param request [Net::HTTPGenericRequest]
  # @param host [String]
  # @param port [Integer]
  # @param ssl [Boolean]
  # @return [Net::HTTPResponse]
  sig do
    params(request: Net::HTTPGenericRequest, host: String, port: Integer, ssl: T::Boolean).returns(Net::HTTPResponse)
  end
  def perform(request, host, port, ssl)
    scheme, default_port = ssl ? ['https', 443] : ['http', 80]
    url = "#{scheme}://#{host}#{":#{port}" unless port == default_port}#{request.path}"
    headers = request.each_header.to_h
    @requests << Request.new(verb: request.method, url:, headers:)
    @responses.fetch("#{request.method} #{url}") { raise(KeyError, "no response for #{request.method} #{url}") }
  end
end
