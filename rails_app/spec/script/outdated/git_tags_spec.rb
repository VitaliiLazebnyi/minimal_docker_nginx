# typed: strict
# frozen_string_literal: true

# Copyright (c) 2026 Vitalii Lazebnyi

require_relative '../../../../script/outdated/git_tags'
require_relative '../../support/git_repository'

RSpec.describe(Outdated::GitTags) do
  sig { returns(String) }
  let(:tag) { 'a' * 40 }

  sig { returns(String) }
  let(:commit) { 'c' * 40 }

  describe '.of' do
    it 'maps every tag of the repository to its commit, annotated tags to the commit they point to' do
      Dir.mktmpdir do |directory|
        commit = GitRepository.init(directory)
        expect(described_class.of(directory).to_a).to(eq([['v1.0', commit], ['v1.1', commit]]))
      end
    end

    it 'raises when the repository cannot be listed' do
      allow(Open3).to(receive(:capture2).and_return(['', instance_double(Process::Status, success?: false)]))
      expect { described_class.of('https://example.invalid/repository') }
        .to(raise_error(Outdated::Error, 'git ls-remote https://example.invalid/repository failed'))
    end
  end

  describe '.peel' do
    it 'maps a lightweight tag to its commit' do
      expect(described_class.peel([[commit, 'refs/tags/v1']]).to_a).to(eq([['v1', commit]]))
    end

    it 'maps an annotated tag to the commit it points to when the peeled line comes after the tag' do
      expect(described_class.peel([[tag, 'refs/tags/v1'], [commit, 'refs/tags/v1^{}']]).to_a).to(eq([['v1', commit]]))
    end

    it 'maps an annotated tag to the commit it points to when the peeled line comes first' do
      expect(described_class.peel([[commit, 'refs/tags/v1^{}'], [tag, 'refs/tags/v1']]).to_a).to(eq([['v1', commit]]))
    end
  end
end
