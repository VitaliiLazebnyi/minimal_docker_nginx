# typed: strict
# frozen_string_literal: true

# Copyright (c) 2026 Vitalii Lazebnyi

require_relative '../../../../script/outdated/bundle'
require_relative '../../support/fake_https'
require_relative '../../support/script_repository'

RSpec.describe(Outdated::Bundle) do
  sig { returns(String) }
  let(:root) { Dir.mktmpdir }

  after { FileUtils.remove_entry(root) }

  describe '.bundle_outdated' do
    sig { returns(T::Array[T.any(String, T::Hash[String, String])]) }
    let(:command) { [[%w[BUNDLE_DEPLOYMENT false], %w[BUNDLE_FROZEN false]].to_h, 'bundle', 'outdated', '--parseable'] }

    before { allow(Open3).to(receive(:capture2e).and_return(Open3.capture2e('true'))) }

    it 'runs `bundle outdated --parseable` in the application, out of deployment and frozen mode' do
      described_class.bundle_outdated
      expect(Open3).to(have_received(:capture2e).with(*command, chdir: Outdated::APP))
    end
  end

  describe '.outdated_gems' do
    sig { returns(String) }
    let(:output) do
      "Fetching\nprism (newest 2.1.0, installed 1.9.0, requested ~> 1.7)\nrack (newest 3.2.9, installed 3.2.8)\n"
    end

    sig { returns(T.nilable(Integer)) }
    let(:exitstatus) { 1 }

    before do
      status = instance_double(Process::Status, exitstatus:)
      allow(described_class).to(receive(:bundle_outdated).and_return([output, status]))
    end

    it 'returns the name, newest release and installed version of every outdated gem' do
      expect(described_class.outdated_gems).to(eq([%w[prism 2.1.0 1.9.0], %w[rack 3.2.9 3.2.8]]))
    end

    context 'when every gem is current' do
      sig { returns(String) }
      let(:output) { "Bundle up to date!\n" }

      sig { returns(T.nilable(Integer)) }
      let(:exitstatus) { 0 }

      it 'returns no gem' do
        expect(described_class.outdated_gems).to(eq([]))
      end
    end

    context 'when bundle outdated fails' do
      sig { returns(String) }
      let(:output) { 'Could not find gem' }

      sig { returns(T.nilable(Integer)) }
      let(:exitstatus) { 2 }

      it 'raises, with its output' do
        expect { described_class.outdated_gems }
          .to(raise_error(Outdated::Error, "bundle outdated failed (2):\nCould not find gem"))
      end
    end

    context 'when bundle outdated was killed' do
      sig { returns(T.nilable(Integer)) }
      let(:exitstatus) { nil }

      it 'raises' do
        expect { described_class.outdated_gems }
          .to(raise_error(Outdated::Error, /\Abundle outdated failed \(2\):/))
      end
    end
  end

  describe '#check' do
    sig { returns(FakeHttps) }
    let(:https) { FakeHttps.new }

    sig { returns(Outdated::Report) }
    let(:report) { Outdated::Report.new }

    sig { returns(T::Array[[String, String]]) }
    let(:holds) { [%w[prism 2.1.0]] }

    before do
      https.install(self)
      https.answer(
        'GET',
        'https://rubygems.org/api/v1/versions/bundler/latest.json',
        FakeHttps.json('{"version": "4.0.23"}')
      )
      https.answer(
        'GET',
        'https://rubygems.org/api/v1/versions/rubygems-update/latest.json',
        FakeHttps.json('{"version": "4.0.10"}')
      )
      ScriptRepository.install(
        self,
        root,
        ['Dockerfile', "ARG RUBYGEMS_VERSION=4.0.9\nARG PASSENGER_VERSION=6.2.1\n"],
        ['rails_app/Gemfile.lock', "GEM\n    passenger (6.2.1)\n\nBUNDLED WITH\n   4.0.23\n"]
      )
      allow(described_class).to(receive(:outdated_gems).and_return([%w[prism 2.1.0 1.9.0], %w[rack 3.2.9 3.2.8]]))
      %i[compare info problem].each { |method| allow(report).to(receive(method)) }
      described_class.new(report, holds.to_h).check
    end

    it 'reports a held gem held back from exactly its newest release as information' do
      expect(report).to(have_received(:info).with('gem prism 1.9.0 (newest 2.1.0, on hold)'))
    end

    it 'keeps the hold of a gem that is still outdated' do
      expect(report).not_to(have_received(:problem).with(/stale hold/))
    end

    it 'reports an outdated gem that is not held' do
      expect(report).to(have_received(:problem).with('gem rack 3.2.8 -> 3.2.9 is not on the hold list'))
    end

    it 'compares Bundler with its newest release' do
      expect(report).to(have_received(:compare).with('Bundler (Gemfile.lock, BUNDLED WITH)', '4.0.23', '4.0.23'))
    end

    it 'compares the RubyGems of the Dockerfile with its newest release' do
      expect(report).to(have_received(:compare).with('RubyGems (Dockerfile ARG RUBYGEMS_VERSION)', '4.0.9', '4.0.10'))
    end

    it 'compares the Passenger of the Dockerfile with that of Gemfile.lock' do
      label = 'Passenger (Dockerfile ARG PASSENGER_VERSION, must match Gemfile.lock)'
      expect(report).to(have_received(:compare).with(label, '6.2.1', '6.2.1'))
    end

    context 'with a gem held back from another release than its newest one' do
      sig { returns(T::Array[[String, String]]) }
      let(:holds) { [%w[prism 2.0.0]] }

      it 'reports the gem' do
        expect(report).to(have_received(:problem).with('gem prism 1.9.0 -> 2.1.0 is not on the hold list'))
      end
    end

    context 'with a hold of a gem that is no longer outdated' do
      sig { returns(T::Array[[String, String]]) }
      let(:holds) { [%w[rails 9.0.0]] }

      it 'reports the hold' do
        expect(report).to(have_received(:problem).with('stale hold: gem rails is no longer outdated'))
      end
    end
  end
end
