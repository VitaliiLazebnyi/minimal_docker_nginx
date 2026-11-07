# typed: strict
# frozen_string_literal: true

# Copyright (c) 2026 Vitalii Lazebnyi

require_relative '../../../script/outdated'
require_relative '../support/fake_https'
require_relative '../support/script_repository'

RSpec.describe(Outdated) do
  sig { returns(String) }
  let(:root) { Dir.mktmpdir }

  after { FileUtils.remove_entry(root) }

  describe 'ROOT' do
    it 'is the root of the repository' do
      expect(Outdated::ROOT).to(eq(File.expand_path('../../..', __dir__)))
    end
  end

  describe 'APP' do
    it 'is the directory of the Rails application' do
      expect(Outdated::APP).to(eq(Rails.root.to_s))
    end
  end

  describe 'PINNING_FILES' do
    it 'lists the Dockerfile and every workflow' do
      expect(Outdated::PINNING_FILES.map { |path| described_class.relative(path) })
        .to(include('Dockerfile', '.github/workflows/ci.yml', '.github/workflows/security.yml'))
    end
  end

  describe '.relative' do
    it 'removes the repository root from a path' do
      expect(described_class.relative(File.join(Outdated::ROOT, 'tools', 'images.json'))).to(eq('tools/images.json'))
    end

    it 'leaves a path outside the repository alone' do
      expect(described_class.relative('/elsewhere/tools/images.json')).to(eq('/elsewhere/tools/images.json'))
    end
  end

  describe '.newest' do
    it 'returns the highest version by version order, not by text' do
      expect(described_class.newest(%w[1.9.0 1.10.0 1.2.0])).to(eq('1.10.0'))
    end

    it 'returns an empty string when there is no version' do
      expect(described_class.newest([])).to(eq(''))
    end
  end

  describe '.matches' do
    it 'returns the match of each line that has one' do
      matches = described_class.matches("a=1\nb\nc=2\n", /(?<key>\w)=(?<value>\d)/)
      expect(matches.map(&:to_s)).to(eq(%w[a=1 c=2]))
    end
  end

  describe '.group' do
    it 'returns the text of the named group' do
      match = described_class.matches('a=', /(?<key>\w)=/).fetch(0)
      expect(described_class.group(match, 'key')).to(eq('a'))
    end

    it 'raises when the group took no part in the match, naming the pattern and the match' do
      match = described_class.matches('=', /(?<key>\w)?=/).fetch(0)
      expect { described_class.group(match, 'key') }
        .to(raise_error(Outdated::Error, '/(?<key>\w)?=/ matched "=" without key'))
    end
  end

  describe '.extract' do
    it 'returns the group "value" of the first match' do
      expect(described_class.extract("x 1\nv 2\nv 3\n", /^v (?<value>\d)/)).to(eq('2'))
    end

    it 'raises when nothing matches, naming the pattern' do
      expect { described_class.extract('x 1', /^v (?<value>\d)/) }
        .to(raise_error(Outdated::Error, 'no match of /^v (?<value>\d)/'))
    end
  end

  describe '.dockerfile_arg' do
    before do
      ScriptRepository.install(self, root, ['Dockerfile', "ARG NGINX_VERSION_OLD=1\nARG NGINX_VERSION=1.29.3\n"])
    end

    it 'returns the value of the build argument' do
      expect(described_class.dockerfile_arg('NGINX_VERSION')).to(eq('1.29.3'))
    end

    it 'raises when the Dockerfile has no such argument' do
      expect { described_class.dockerfile_arg('PASSENGER_VERSION') }
        .to(raise_error(Outdated::Error, 'no match of /^ARG PASSENGER_VERSION=(?<value>\S+)$/'))
    end
  end

  describe '.checks' do
    sig { returns(FakeHttps) }
    let(:https) { FakeHttps.new }

    sig { returns(Outdated::Report) }
    let(:report) { Outdated::Report.new }

    sig { returns(Object) }
    let(:holds) { Outdated::Document.parse('{"gems": {"prism": {"newest": "2.1.0"}}, "ruby_lines": {"3.3": {}}}') }

    before do
      https.install(self)
      https.answer('GET', 'https://cache.ruby-lang.org/pub/ruby/index.txt', FakeHttps.response('200 OK'))
      ScriptRepository.install(self, root, ['rails_app/Gemfile.lock', ''])
      allow(Outdated::Bundle).to(receive(:new).and_call_original)
      allow(Outdated::Rubies).to(receive(:new).and_call_original)
    end

    it 'checks the gems, Ruby, nginx, the images, the actions and the tools, in that order' do
      checks = described_class.checks(report, holds).map { |check| check.class.name.to_s.delete_prefix('Outdated::') }
      expect(checks).to(eq(%w[Bundle Rubies Nginx Images Actions Tools]))
    end

    it 'gives the gem check the held gems, each with the newest release it is held back from' do
      described_class.checks(report, holds)
      expect(Outdated::Bundle).to(have_received(:new).with(report, [%w[prism 2.1.0]].to_h))
    end

    it 'gives the Ruby check the Ruby lines on hold' do
      described_class.checks(report, holds)
      expect(Outdated::Rubies).to(have_received(:new).with(report, ['3.3']))
    end
  end

  describe '.run' do
    sig { returns(T::Boolean) }
    let(:failing) { false }

    before do
      ScriptRepository.install(self, root, ['script/outdated_holds.yml', "gems: {}\nruby_lines: {}\n"])
      allow(described_class).to(receive(:checks)) { |report, _holds| [CheckStub.new(self, report, failing)] }
    end

    it 'returns 0 when every check passes' do
      expect(described_class.run).to(eq(0))
    end

    it 'gives the checks the holds of script/outdated_holds.yml' do
      described_class.run
      holds = Outdated::Document.parse('{"gems": {}, "ruby_lines": {}}')
      expect(described_class).to(have_received(:checks).with(Outdated::Report, holds))
    end

    context 'when a check fails' do
      sig { returns(T::Boolean) }
      let(:failing) { true }

      it 'returns 1' do
        expect(described_class.run).to(eq(1))
      end
    end
  end
end
