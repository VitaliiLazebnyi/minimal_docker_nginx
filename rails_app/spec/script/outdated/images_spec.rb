# typed: strict
# frozen_string_literal: true

# Copyright (c) 2026 Vitalii Lazebnyi

require_relative '../../../../script/outdated/images'
require_relative '../../support/fake_https'
require_relative '../../support/script_repository'
require_relative '../../support/tag_pages'

RSpec.describe(Outdated::Images) do
  sig { returns(String) }
  let(:root) { Dir.mktmpdir }

  sig { returns(String) }
  let(:digest) { "sha256:#{'a' * 64}" }

  sig { returns(String) }
  let(:images) { %({"$comment": ["x"], "trivy": {"name": "aquasec/trivy", "tag": "0.76.2", "digest": "#{digest}"}}) }

  sig { returns(FakeHttps) }
  let(:https) { FakeHttps.new }

  after { FileUtils.remove_entry(root) }

  before do
    https.install(self)
    ScriptRepository.install(
      self,
      root,
      ['Dockerfile', "FROM ghcr.io/org/image:1.0@#{digest} AS builder\nFROM scratch\n"],
      ['.github/workflows/a.yml', "image: x/y:v2@#{digest}\n"],
      ['tools/images.json', images]
    )
  end

  describe '.pins_in' do
    it 'finds every image pinned as name:tag@digest, with the file it is pinned in' do
      pins = described_class.pins_in(File.join(root, 'Dockerfile'))
      expect(pins.map { |pin| [pin.location, pin.name, pin.tag, pin.digest] })
        .to(eq([['Dockerfile', 'ghcr.io/org/image', '1.0', digest]]))
    end
  end

  describe '.pins_in_json' do
    it 'reads the images of tools/images.json, without its comment' do
      pins = described_class.pins_in_json(File.join(root, 'tools/images.json'))
      expect(pins.map { |pin| [pin.location, pin.name, pin.tag, pin.digest] })
        .to(eq([['tools/images.json trivy', 'aquasec/trivy', '0.76.2', digest]]))
    end
  end

  describe '.pins' do
    it 'finds the images of the Dockerfile, of the workflows and of tools/images.json' do
      expect(described_class.pins.map(&:location))
        .to(eq(['Dockerfile', '.github/workflows/a.yml', 'tools/images.json trivy']))
    end
  end

  describe '.newest_tag' do
    it 'returns the highest tag of the same shape, comparing the numbers' do
      tags = %w[4.0.9-alpine3.24 4.0.10-alpine3.24 4.0.8-alpine3.25 4.0.9-slim 4-alpine3.24 latest]
      expect(described_class.newest_tag(tags, '4.0.9-alpine3.24')).to(eq('4.0.10-alpine3.24'))
    end

    it 'compares the text between the numbers literally' do
      expect(described_class.newest_tag(%w[1.0 1x1], '1.0')).to(eq('1.0'))
    end

    it 'requires a tag of the same shape to end where the pinned one ends' do
      expect(described_class.newest_tag(%w[1.0 1.0.1 1.0rc], '1.0')).to(eq('1.0'))
    end

    it 'compares every number of the tags, whatever its number of digits' do
      expect(described_class.newest_tag(%w[1.10 2.0 1.9], '1.10')).to(eq('2.0'))
    end

    it 'returns the pinned tag when no tag has its shape' do
      expect(described_class.newest_tag(['latest'], 'v1.0')).to(eq('v1.0'))
    end
  end

  describe '.version' do
    it 'returns the numbers of the tag, in order, as a version' do
      expect(described_class.version('v4.0.9-alpine3.24')).to(eq(Gem::Version.new('4.0.9.3.24')))
    end
  end

  describe '#check' do
    before do
      ScriptRepository.install(self, root, ['.github/workflows/a.yml', ''], ['tools/images.json', '{}'])
      https.answer('GET', 'https://ghcr.io/v2/', FakeHttps.response('200 OK'))
      https.answer('GET', 'https://ghcr.io/v2/org/image/tags/list?n=1000', TagPages.page(%w[1.0 1.1]))
      https.answer(
        'HEAD',
        'https://ghcr.io/v2/org/image/manifests/1.0',
        FakeHttps.response('200 OK', headers: [['Docker-Content-Digest', digest]])
      )
    end

    it 'reports an image whose tag is not the newest' do
      expect { described_class.new(Outdated::Report.new).check }
        .to(output("OUTDATED: image tag of ghcr.io/org/image:1.0 (Dockerfile) 1.0 -> 1.1\n").to_stderr)
    end

    it 'accepts the digest the tag points to' do
      expect { described_class.new(Outdated::Report.new).check }
        .to(output("image digest of ghcr.io/org/image:1.0 (Dockerfile) #{digest}\n").to_stdout)
    end
  end
end
