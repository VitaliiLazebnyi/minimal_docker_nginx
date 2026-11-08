# typed: strict
# frozen_string_literal: true

# Copyright (c) 2026 Vitalii Lazebnyi

require_relative '../../../../script/outdated/actions'
require_relative '../../support/script_repository'

RSpec.describe(Outdated::Actions) do
  sig { returns(String) }
  let(:root) { Dir.mktmpdir }

  sig { returns(String) }
  let(:commit) { 'c' * 40 }

  after { FileUtils.remove_entry(root) }

  before do
    workflow = "steps:\n  - uses: actions/checkout@#{commit}  # v7.0.1\n  " \
      "- uses: github/codeql-action/init@#{commit} # v4.1.0\n"
    ScriptRepository.install(
      self,
      root,
      ['Dockerfile', ''],
      ['.github/workflows/a.yml', workflow],
      ['.github/workflows/b.yml', "- uses: actions/checkout@#{commit} # v7.0.1\n"]
    )
  end

  describe '.references' do
    it 'returns every action reference of the workflows: repository, commit and tag' do
      expect(described_class.references.map(&:last)).to(eq(%w[v7.0.1 v4.1.0 v7.0.1]))
    end

    it 'returns the repository and the commit of each reference' do
      expect(described_class.references.first(2))
        .to(eq([['actions/checkout', commit, 'v7.0.1'], ['github/codeql-action', commit, 'v4.1.0']]))
    end
  end

  describe '#check' do
    sig { returns(Outdated::Report) }
    let(:report) { Outdated::Report.new }

    before do
      tags = [['v7.0.1', commit], ['v7.1.0', 'd' * 40], ['v8.0.0-beta', 'e' * 40], ['latest', 'f' * 40]].to_h
      allow(Outdated::GitTags).to(receive(:of).with('https://github.com/actions/checkout').and_return(tags))
      allow(Outdated::GitTags).to(
        receive(:of).with('https://github.com/github/codeql-action').and_return(
          [
            [
              'v4.0.0',
              commit
            ]
          ].to_h
        )
      )
      allow(report).to(receive(:compare))
      described_class.new(report).check
    end

    it 'checks each action once' do
      expect(Outdated::GitTags).to(have_received(:of).with('https://github.com/actions/checkout').once)
    end

    it 'compares the tag of an action with its newest release tag' do
      expect(report).to(have_received(:compare).with('action actions/checkout tag', 'v7.0.1', 'v7.1.0'))
    end

    it 'compares the commit of an action with the commit its tag points to' do
      expect(report).to(have_received(:compare).with('action actions/checkout@v7.0.1 commit', commit, commit))
    end

    it 'reports the commit of a tag that does not exist' do
      expect(report)
        .to(have_received(:compare).with('action github/codeql-action@v4.1.0 commit', commit, 'no such tag'))
    end
  end
end
