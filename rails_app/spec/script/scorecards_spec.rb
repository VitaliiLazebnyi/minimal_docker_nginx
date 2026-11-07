# typed: strict
# frozen_string_literal: true

# Copyright (c) 2026 Vitalii Lazebnyi

require_relative '../../../script/scorecards'
require_relative '../support/fake_https'
require_relative '../support/script_repository'

RSpec.describe(Scorecards) do
  sig { returns(String) }
  let(:root) { Dir.mktmpdir }

  sig { returns(FakeHttps) }
  let(:https) { FakeHttps.new }

  sig { returns(Outdated::Report) }
  let(:report) { Outdated::Report.new('SCORECARD') }

  after { FileUtils.remove_entry(root) }

  before do
    https.install(self)
    allow(report).to(receive(:info))
    allow(report).to(receive(:problem))
  end

  describe '.added' do
    it 'returns the added dependencies, with their repository' do
      added = described_class.added(%([#{DependencyChanges.added}, {"change_type": "removed"}]))
      expect(added.map { |dependency| dependency.serialize.values }).to(eq([%w[rubygems a 1 https://github.com/o/a]]))
    end

    it 'gives a dependency without a source repository an empty one' do
      expect(described_class.added(DependencyChanges.npm).map(&:repository)).to(eq(['']))
    end

    it 'raises when the changes are not a list, naming them' do
      expect { described_class.added('"x"') }
        .to(raise_error(ArgumentError, 'the dependency changes are not a list: "x"'))
    end
  end

  describe '.score' do
    it 'returns the Scorecard score of the repository, as a float' do
      https.answer('GET', DependencyChanges::SCORECARD, FakeHttps.json('{"score": 7}'))
      expect(described_class.score('github.com/o/a')).to(be(7.0))
    end

    it 'returns nil when Scorecard has not scored the repository' do
      https.answer('GET', DependencyChanges::SCORECARD, FakeHttps.response('404 Not Found'))
      expect(described_class.score('github.com/o/a')).to(be_nil)
    end

    it 'returns nil when the score is not a number' do
      https.answer('GET', DependencyChanges::SCORECARD, FakeHttps.json('{"score": "7"}'))
      expect(described_class.score('github.com/o/a')).to(be_nil)
    end
  end

  describe '.first_project' do
    it 'returns the first project deps.dev relates to the version' do
      document = Outdated::Document.parse('{"relatedProjects": [{"projectKey": {"id": "github.com/o/a"}}, {}]}')
      expect(described_class.first_project(document)).to(eq('github.com/o/a'))
    end

    it 'returns nil when deps.dev relates no project to the version' do
      expect(described_class.first_project(Outdated::Document.parse('{"relatedProjects": []}'))).to(be_nil)
    end
  end

  describe '.check' do
    sig { returns(String) }
    let(:allowances) { "{}\n" }

    sig { returns(String) }
    let(:changes) { "[#{DependencyChanges.added}]" }

    before do
      https.answer('GET', DependencyChanges::SCORECARD, FakeHttps.json('{"score": 2}'))
      ScriptRepository.install(
        self,
        root,
        ['script/scorecard_allowances.yml', allowances],
        ['rails_app/Gemfile.lock', "    a (1)\n"],
        ['tools/requirements.txt', "abc==1\nc==1\n"]
      )
    end

    it 'reports a dependency below the threshold that is not allowed' do
      described_class.check(report, Scorecards::Allowances.load, changes)
      message = 'rubygems/a 1 (github.com/o/a): Scorecard 2.0 is below 3.0 and not in script/scorecard_allowances.yml'
      expect(report).to(have_received(:problem).with(message))
    end

    it 'checks a dependency added twice once' do
      twice = "[#{DependencyChanges.added}, #{DependencyChanges.added}]"
      described_class.check(report, Scorecards::Allowances.load, twice)
      expect(report).to(have_received(:problem).once)
    end

    context 'with an allowance' do
      sig { returns(String) }
      let(:allowances) { "rubygems/a:\n  reason: needed\n" }

      it 'keeps the allowance of a dependency below the threshold' do
        described_class.check(report, Scorecards::Allowances.load, changes)
        expect(report).not_to(have_received(:problem))
      end

      it 'accepts a dependency below the threshold, with the reason' do
        described_class.check(report, Scorecards::Allowances.load, changes)
        expect(report).to(have_received(:info).with('rubygems/a 1 (github.com/o/a): Scorecard 2.0, allowed: needed'))
      end

      it 'reports the allowance once the dependency reaches the threshold' do
        https.answer('GET', DependencyChanges::SCORECARD, FakeHttps.json('{"score": 3}'))
        described_class.check(report, Scorecards::Allowances.load, changes)
        expect(report).to(have_received(:problem).with('stale allowance: rubygems/a now scores 3.0 or more'))
      end
    end

    context 'with a dependency that Scorecard has not scored' do
      sig { returns(String) }
      let(:allowances) { "rubygems/a:\n  reason: needed\n" }

      before do
        https.answer('GET', DependencyChanges::SCORECARD, FakeHttps.response('404 Not Found'))
        described_class.check(report, Scorecards::Allowances.load, changes)
      end

      it 'accepts the dependency' do
        expect(report).to(have_received(:info).with('rubygems/a 1 (github.com/o/a): Scorecard none'))
      end

      it 'keeps its allowance' do
        expect(report).not_to(have_received(:problem))
      end
    end

    context 'with a dependency at the threshold' do
      before do
        https.answer('GET', DependencyChanges::SCORECARD, FakeHttps.json('{"score": 3}'))
        described_class.check(report, Scorecards::Allowances.load, changes)
      end

      it 'accepts the dependency' do
        expect(report).to(have_received(:info).with('rubygems/a 1 (github.com/o/a): Scorecard 3.0'))
      end

      it 'reports nothing when the dependency has no allowance' do
        expect(report).not_to(have_received(:problem))
      end
    end

    context 'with allowances of packages that are in no lockfile' do
      sig { returns(String) }
      let(:allowances) do
        "pip/c:\n  reason: x\nrubygems/a:\n  reason: y\nrubygems/d:\n  reason: z\npip/a.c:\n  reason: w\n"
      end

      before { described_class.check(report, Scorecards::Allowances.load, '[]') }

      it 'reports an allowance whose package is in no lockfile' do
        expect(report).to(have_received(:problem).with('stale allowance: rubygems/d is in no lockfile'))
      end

      it 'reads the name of the package literally' do
        expect(report).to(have_received(:problem).with('stale allowance: pip/a.c is in no lockfile'))
      end

      it 'keeps the allowances of the packages of any lockfile' do
        expect(report).to(have_received(:problem).twice)
      end
    end

    context 'with a dependency without a source repository' do
      before do
        ScriptRepository.install(
          self,
          root,
          ['script/scorecard_allowances.yml', "{}\n"],
          ['rails_app/Gemfile.lock', ''],
          ['tools/requirements.txt', '']
        )
        https.answer(
          'GET',
          'https://api.securityscorecards.dev/projects/github.com/s/p',
          FakeHttps.json('{"score": 8.5}')
        )
      end

      it 'scores the repository deps.dev relates to the version' do
        related = FakeHttps.json('{"relatedProjects": [{"projectKey": {"id": "github.com/s/p"}}]}')
        https.answer('GET', DependencyChanges::NPM_VERSION, related)
        described_class.check(report, Scorecards::Allowances.load, DependencyChanges.npm)
        expect(report).to(have_received(:info).with('npm/@s/p 1 (github.com/s/p): Scorecard 8.5'))
      end

      it 'names no repository when deps.dev does not know the version' do
        https.answer('GET', DependencyChanges::NPM_VERSION, FakeHttps.response('404 Not Found'))
        described_class.check(report, Scorecards::Allowances.load, DependencyChanges.npm)
        expect(report).to(have_received(:info).with('npm/@s/p 1 (no repository): Scorecard none'))
      end
    end
  end

  describe '.run' do
    sig { returns(String) }
    let(:allowances) { "{}\n" }

    before do
      ScriptRepository.install(
        self,
        root,
        ['script/scorecard_allowances.yml', allowances],
        ['rails_app/Gemfile.lock', ''],
        ['tools/requirements.txt', '']
      )
      allow(Outdated::Report).to(receive(:new).with('SCORECARD').and_return(report))
      allow(report).to(receive(:problem).and_call_original)
      allow(report).to(receive(:warn))
      stub_const('ENV', ENV.to_h.except('DEPENDENCY_CHANGES'))
    end

    it 'checks the changes of DEPENDENCY_CHANGES' do
      stub_const('ENV', ENV.to_h.merge([%w[DEPENDENCY_CHANGES {}]].to_h))
      expect { described_class.run }
        .to(raise_error(ArgumentError, 'the dependency changes are not a list: {}'))
    end

    it 'returns 0 when every check passes' do
      expect(described_class.run).to(eq(0))
    end

    context 'when a check fails' do
      sig { returns(String) }
      let(:allowances) { "rubygems/gone:\n  reason: x\n" }

      it 'returns 1' do
        expect(described_class.run).to(eq(1))
      end
    end
  end
end
