# typed: strict
# frozen_string_literal: true

# Copyright (c) 2026 Vitalii Lazebnyi

require_relative '../../../../script/outdated/tools'
require_relative '../../support/fake_https'
require_relative '../../support/script_repository'

RSpec.describe(Outdated::Tools) do
  sig { returns(String) }
  let(:root) { Dir.mktmpdir }

  after { FileUtils.remove_entry(root) }

  describe '.newest_release' do
    before do
      tags = %w[v3.9.0 v3.14.1 v4.0.0-rc1 go1.0 v3].index_with('a' * 40)
      allow(Outdated::GitTags).to(receive(:of).with('https://github.com/mvdan/sh').and_return(tags))
    end

    it 'returns the newest version among the release tags of the repository' do
      expect(described_class.newest_release('mvdan/sh')).to(eq('3.14.1'))
    end
  end

  describe '#check' do
    sig { returns(FakeHttps) }
    let(:https) { FakeHttps.new }

    sig { returns(Outdated::Report) }
    let(:report) { Outdated::Report.new }

    before do
      https.install(self)
      https.answer('GET', 'https://pypi.org/pypi/zizmor/json', FakeHttps.json('{"info": {"version": "1.33.0"}}'))
      ScriptRepository.install(
        self,
        root,
        ['tools/requirements.txt', "# comment\nzizmor==1.32.0 \\\n    --hash=sha256:a\n"],
        ['tools/binaries.json', '{"$comment": [], "shfmt": {"repository": "mvdan/sh", "version": "3.14.1"}}']
      )
      allow(described_class).to(receive(:newest_release).with('mvdan/sh').and_return('3.15.0'))
      allow(report).to(receive(:compare))
      described_class.new(report).check
    end

    it 'compares every Python package of tools/requirements.txt with its newest release on PyPI' do
      expect(report)
        .to(have_received(:compare).with('Python package zizmor (tools/requirements.txt)', '1.32.0', '1.33.0'))
    end

    it 'compares every binary of tools/binaries.json with the newest release of its repository' do
      expect(report).to(have_received(:compare).with('shfmt (tools/binaries.json)', '3.14.1', '3.15.0'))
    end
  end
end
