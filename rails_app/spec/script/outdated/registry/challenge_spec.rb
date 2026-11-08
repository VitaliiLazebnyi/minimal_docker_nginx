# typed: strict
# frozen_string_literal: true

# Copyright (c) 2026 Vitalii Lazebnyi

require_relative '../../../../../script/outdated/registry'

RSpec.describe(Outdated::Registry::Challenge) do
  describe '#token_url' do
    it 'names the service and the pull scope of the repository at the realm' do
      challenge = described_class.new('Bearer realm="https://auth.example/token", service="registry.example"')
      expect(challenge.token_url('host.example', 'org/image'))
        .to(eq('https://auth.example/token?service=registry.example&scope=repository%3Aorg%2Fimage%3Apull'))
    end

    it 'reads fields separated by a comma alone' do
      challenge = described_class.new('Bearer realm="https://auth.example/token",service="registry.example"')
      expect(challenge.token_url('host.example', 'a'))
        .to(start_with('https://auth.example/token?service=registry.example&'))
    end

    it 'names the registry host as the service when the challenge names none' do
      expect(described_class.new('Bearer realm="https://ghcr.io/token"').token_url('ghcr.io', 'a'))
        .to(eq('https://ghcr.io/token?service=ghcr.io&scope=repository%3Aa%3Apull'))
    end

    it 'raises when the challenge names no realm' do
      expect { described_class.new('Bearer service="ghcr.io"').token_url('ghcr.io', 'a') }
        .to(raise_error(KeyError, 'key not found: "realm"'))
    end
  end
end
