# typed: strict
# frozen_string_literal: true

# Copyright (c) 2026 Vitalii Lazebnyi

require_relative '../../../../script/outdated/http'
require_relative '../../support/fake_https'

RSpec.describe(Outdated::Http) do
  sig { returns(FakeHttps) }
  let(:https) { FakeHttps.new }

  sig { returns(String) }
  let(:url) { 'https://example.com/v2/' }

  before { https.install(self) }

  describe '.get' do
    it 'returns the response of a successful request, made with TLS' do
      https.answer('GET', url, FakeHttps.response('200 OK', body: 'body'))
      expect(described_class.get(url).body).to(eq('body'))
    end

    it 'sends the headers' do
      https.answer('GET', url, FakeHttps.response('200 OK'))
      described_class.get(url, Accept: 'application/json')
      expect(https.last_request.header('accept')).to(eq('application/json'))
    end

    it 'returns a 401 Unauthorized response, which asks for a token' do
      https.answer('GET', url, FakeHttps.response('401 Unauthorized'))
      expect(described_class.get(url)).to(be_a(Net::HTTPUnauthorized))
    end

    it 'raises on any other response, naming the URL and the status' do
      https.answer('GET', url, FakeHttps.response('500 Internal Server Error'))
      expect { described_class.get(url) }
        .to(raise_error(Outdated::Error, "#{url}: 500 Internal Server Error"))
    end

    it 'raises on a 404 Not Found response' do
      https.answer('GET', url, FakeHttps.response('404 Not Found'))
      expect { described_class.get(url) }
        .to(raise_error(Outdated::Error, "#{url}: 404 Not Found"))
    end

    context 'when the server redirects' do
      before do
        https.answer('GET', url, FakeHttps.response('302 Found', headers: [%w[Location /1]]))
        (1..4).each do |hop|
          https.answer(
            'GET',
            "https://example.com/#{hop}",
            FakeHttps.response('302 Found', headers: [['Location', "/#{hop + 1}"]])
          )
        end
      end

      it 'follows up to five redirects, relative to the URL that redirected' do
        https.answer('GET', 'https://example.com/5', FakeHttps.response('200 OK', body: 'moved'))
        expect(described_class.get(url).body).to(eq('moved'))
      end

      it 'sends the headers to the new location' do
        https.answer('GET', 'https://example.com/1', FakeHttps.response('200 OK'))
        described_class.get(url, Accept: 'text/plain')
        expect(https.requests.map { |request| request.header('accept') }).to(eq(%w[text/plain text/plain]))
      end

      it 'raises on a sixth redirect, naming its location' do
        https.answer('GET', 'https://example.com/5', FakeHttps.response('302 Found', headers: [%w[Location /6]]))
        expect { described_class.get(url) }
          .to(raise_error(Outdated::Error, 'https://example.com/6: more than 5 redirects'))
      end
    end
  end

  describe '.find' do
    it 'returns nil when the server answers 404 Not Found' do
      https.answer('GET', url, FakeHttps.response('404 Not Found'))
      expect(described_class.find(url)).to(be_nil)
    end

    it 'returns the response of a successful request' do
      https.answer('GET', url, FakeHttps.response('200 OK', body: 'found'))
      expect(described_class.find(url)&.body).to(eq('found'))
    end

    it 'raises on any other response' do
      https.answer('GET', url, FakeHttps.response('503 Service Unavailable'))
      expect { described_class.find(url) }
        .to(raise_error(Outdated::Error, "#{url}: 503 Service Unavailable"))
    end
  end

  describe '.head' do
    it 'sends a HEAD request and returns its response' do
      https.answer('HEAD', url, FakeHttps.response('200 OK', headers: [%w[Docker-Content-Digest sha256:1]]))
      expect(described_class.head(url)['docker-content-digest']).to(eq('sha256:1'))
    end

    it 'sends the headers' do
      https.answer('HEAD', url, FakeHttps.response('200 OK'))
      described_class.head(url, Accept: 'a')
      expect(https.last_request.header('accept')).to(eq('a'))
    end

    it 'raises on an unsuccessful response' do
      https.answer('HEAD', url, FakeHttps.response('403 Forbidden'))
      expect { described_class.head(url) }
        .to(raise_error(Outdated::Error, "#{url}: 403 Forbidden"))
    end
  end

  describe '.body' do
    it 'returns the body of the response' do
      expect(described_class.body(FakeHttps.response('200 OK', body: 'text'))).to(eq('text'))
    end

    it 'returns an empty string for a response without a body' do
      expect(described_class.body(FakeHttps.response('204 No Content'))).to(eq(''))
    end
  end

  describe '.document' do
    it 'parses the JSON body of the response' do
      expect(described_class.document(FakeHttps.json('[1]'))).to(eq([1]))
    end
  end

  describe '.json' do
    it 'parses the JSON body of the response' do
      https.answer('GET', url, FakeHttps.json('[1.0]'))
      expect(described_class.json(url)).to(eq([1.0]))
    end

    it 'sends the headers' do
      https.answer('GET', url, FakeHttps.json('{}'))
      described_class.json(url, Authorization: 'Bearer t')
      expect(https.last_request.header('authorization')).to(eq('Bearer t'))
    end
  end
end
