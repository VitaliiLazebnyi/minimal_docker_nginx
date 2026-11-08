# typed: strict
# frozen_string_literal: true

# Copyright (c) 2026 Vitalii Lazebnyi

require_relative '../../../../script/outdated/registry'
require_relative '../../support/fake_https'
require_relative '../../support/tag_pages'

RSpec.describe(Outdated::Registry) do
  sig { returns(FakeHttps) }
  let(:https) { FakeHttps.new }

  before do
    https.install(self)
    https.answer('GET', 'https://ghcr.io/v2/', FakeHttps.response('200 OK'))
    https.answer('GET', 'https://registry-1.docker.io/v2/', FakeHttps.response('200 OK'))
  end

  describe '.for' do
    it 'reads an official Docker Hub image from the library namespace' do
      https.answer('GET', 'https://registry-1.docker.io/v2/library/ruby/tags/list?n=1000', TagPages.page(['4.0.9']))
      expect(described_class.for('ruby').tags).to(eq(['4.0.9']))
    end

    it 'reads another Docker Hub image from its own namespace' do
      https.answer('GET', 'https://registry-1.docker.io/v2/hadolint/hadolint/tags/list?n=1000', TagPages.page(['v2']))
      expect(described_class.for('hadolint/hadolint').tags).to(eq(['v2']))
    end

    it 'reads an image whose name starts with a host from that host' do
      https.answer('GET', 'https://ghcr.io/v2/org/tools/image/tags/list?n=1000', TagPages.page(['1.0']))
      expect(described_class.for('ghcr.io/org/tools/image').tags).to(eq(['1.0']))
    end
  end

  describe '.next_page' do
    it 'returns the URL of the next page, relative to the current one' do
      link = '</v2/a/tags/list?n=2&last=b>; rel="next"'
      expect(described_class.next_page('https://ghcr.io/v2/a/tags/list?n=2', link))
        .to(eq('https://ghcr.io/v2/a/tags/list?n=2&last=b'))
    end

    it 'reads a link without a space before its relation' do
      expect(described_class.next_page('https://ghcr.io/v2/a', '</v2/b>;rel="next"')).to(eq('https://ghcr.io/v2/b'))
    end

    it 'reads a link with several spaces before its relation' do
      expect(described_class.next_page('https://ghcr.io/v2/a', '</v2/b>;  rel="next"')).to(eq('https://ghcr.io/v2/b'))
    end

    it 'returns nil when there is no next page' do
      expect(described_class.next_page('https://ghcr.io/v2/a/tags/list', '')).to(be_nil)
    end
  end

  describe '#tags' do
    sig { returns(String) }
    let(:first_page) { 'https://ghcr.io/v2/org/image/tags/list?n=1000' }

    it 'follows the pagination of the registry' do
      https.answer('GET', first_page, TagPages.page(%w[1 2], next_page: '/v2/n?p=2'))
      https.answer('GET', 'https://ghcr.io/v2/n?p=2', TagPages.page(['3']))
      expect(described_class.new('ghcr.io', 'org/image').tags).to(eq(%w[1 2 3]))
    end

    it 'returns no tag for a repository without tags' do
      https.answer('GET', first_page, FakeHttps.json('{}'))
      expect(described_class.new('ghcr.io', 'org/image').tags).to(eq([]))
    end

    it 'asks once whether the registry needs a token' do
      https.answer('GET', first_page, TagPages.page(['1'], next_page: '/v2/n?p=2'))
      https.answer('GET', 'https://ghcr.io/v2/n?p=2', TagPages.page(['2']))
      described_class.new('ghcr.io', 'org/image').tags
      expect(https.requests.map(&:url).grep('https://ghcr.io/v2/')).to(eq(['https://ghcr.io/v2/']))
    end

    it 'sends no Authorization header when the registry needs no token' do
      https.answer('GET', first_page, TagPages.page(['1']))
      described_class.new('ghcr.io', 'org/image').tags
      expect(https.last_request.header('authorization')).to(be_nil)
    end

    context 'when the registry asks for a token' do
      sig { returns(String) }
      let(:token_service) do
        'https://auth.docker.io/token?service=registry.docker.io&scope=repository%3Alibrary%2Fruby%3Apull'
      end

      before do
        challenge = 'Bearer realm="https://auth.docker.io/token",service="registry.docker.io"'
        https.answer(
          'GET',
          'https://registry-1.docker.io/v2/',
          FakeHttps.response('401 Unauthorized', headers: [['WWW-Authenticate', challenge]])
        )
        https.answer('GET', 'https://registry-1.docker.io/v2/library/ruby/tags/list?n=1000', TagPages.page(['4']))
      end

      it 'sends the pull token the token service issues for the repository' do
        https.answer('GET', token_service, FakeHttps.json('{"token": "t1"}'))
        described_class.for('ruby').tags
        expect(https.last_request.header('authorization')).to(eq('Bearer t1'))
      end

      it 'reads an access token when the service issues no token' do
        https.answer('GET', token_service, FakeHttps.json('{"access_token": "t2"}'))
        described_class.for('ruby').tags
        expect(https.last_request.header('authorization')).to(eq('Bearer t2'))
      end
    end

    context 'when the registry asks for a token without naming its token service' do
      before { https.answer('GET', 'https://ghcr.io/v2/', FakeHttps.response('401 Unauthorized')) }

      it 'raises' do
        expect { described_class.new('ghcr.io', 'org/image') }
          .to(raise_error(KeyError, 'key not found: "www-authenticate"'))
      end
    end
  end

  describe '#digest' do
    sig { returns(String) }
    let(:manifest) { 'https://ghcr.io/v2/org/image/manifests/1.0' }

    it 'returns the digest the tag points to' do
      https.answer('HEAD', manifest, FakeHttps.response('200 OK', headers: [%w[Docker-Content-Digest sha256:1]]))
      expect(described_class.new('ghcr.io', 'org/image').digest('1.0')).to(eq('sha256:1'))
    end

    it 'accepts every manifest and index type, so the digest is that of the tag' do
      https.answer('HEAD', manifest, FakeHttps.response('200 OK'))
      described_class.new('ghcr.io', 'org/image').digest('1.0')
      expect(https.last_request.header('accept')).to(eq(TagPages::MANIFEST_TYPES))
    end

    context 'when the registry asks for a token' do
      before do
        challenge = [['WWW-Authenticate', 'Bearer realm="https://ghcr.io/token"']]
        https.answer('GET', 'https://ghcr.io/v2/', FakeHttps.response('401 Unauthorized', headers: challenge))
        https.answer(
          'GET',
          'https://ghcr.io/token?service=ghcr.io&scope=repository%3Aorg%2Fimage%3Apull',
          FakeHttps.json('{"token": "t"}')
        )
        https.answer('HEAD', manifest, FakeHttps.response('200 OK'))
      end

      it 'sends the pull token' do
        described_class.new('ghcr.io', 'org/image').digest('1.0')
        expect(https.last_request.header('authorization')).to(eq('Bearer t'))
      end
    end

    it 'returns an empty string when the registry names no digest' do
      https.answer('HEAD', manifest, FakeHttps.response('200 OK'))
      expect(described_class.new('ghcr.io', 'org/image').digest('1.0')).to(eq(''))
    end
  end
end
