# typed: strict
# frozen_string_literal: true

# Copyright (c) 2026 Vitalii Lazebnyi

require_relative '../../../../script/outdated/rubies'
require_relative '../../support/fake_https'
require_relative '../../support/script_repository'

RSpec.describe(Outdated::Rubies) do
  sig { returns(String) }
  let(:root) { Dir.mktmpdir }

  sig { returns(FakeHttps) }
  let(:https) { FakeHttps.new }

  sig { returns(Outdated::Report) }
  let(:report) { Outdated::Report.new }

  sig { returns(String) }
  let(:index) { "name\turl\nruby-3.3.12\tx\nruby-3.3.13\tx\nruby-3.3.13\ty\nruby-4.0.9\tx\nruby-4.1.0-preview1\tx\n" }

  after { FileUtils.remove_entry(root) }

  before do
    https.install(self)
    https.answer('GET', 'https://cache.ruby-lang.org/pub/ruby/index.txt', FakeHttps.response('200 OK', body: index))
    workflow = "ruby-version: 3.3.12\nrun: script/check_ruby.sh 3.3.12\n"
    ScriptRepository.install(
      self,
      root,
      ['rails_app/.ruby-version', "4.0.7\n"],
      ['Dockerfile', "FROM ruby:4.0.8-alpine\n"],
      ['.github/workflows/m.yml', workflow]
    )
    allow(report).to(receive(:compare))
    allow(report).to(receive(:problem))
  end

  describe '.pins' do
    it 'finds the Ruby of .ruby-version, of the Dockerfile and of the workflows, each version of a file once' do
      expect(described_class.pins)
        .to(eq([['rails_app/.ruby-version', '4.0.7'], ['Dockerfile', '4.0.8'], ['.github/workflows/m.yml', '3.3.12']]))
    end
  end

  describe '.line_of' do
    it 'returns the release line of a version' do
      expect(described_class.line_of('3.3.13')).to(eq('3.3'))
    end
  end

  describe '#check' do
    it 'compares a Ruby with the newest stable release' do
      described_class.new(report, ['3.3']).check
      expect(report).to(have_received(:compare).with('Ruby (Dockerfile)', '4.0.8', '4.0.9'))
    end

    it 'compares a Ruby of a line on hold with the newest release of that line' do
      described_class.new(report, ['3.3']).check
      expect(report)
        .to(have_received(:compare).with('Ruby (.github/workflows/m.yml, line on hold)', '3.3.12', '3.3.13'))
    end

    it 'compares a Ruby of a line that is not on hold with the newest release' do
      described_class.new(report, []).check
      expect(report).to(have_received(:compare).with('Ruby (.github/workflows/m.yml)', '3.3.12', '4.0.9'))
    end

    it 'keeps a line on hold that a file uses' do
      described_class.new(report, ['3.3']).check
      expect(report).not_to(have_received(:problem))
    end

    it 'reports a line on hold that no file uses' do
      described_class.new(report, %w[3.3 3.4]).check
      expect(report).to(have_received(:problem).once.with('stale hold: no file uses Ruby 3.4 any more'))
    end
  end
end
