# typed: strict
# frozen_string_literal: true

# Copyright (c) 2026 Vitalii Lazebnyi

require_relative '../../../../script/outdated/report'

RSpec.describe(Outdated::Report) do
  describe '#info' do
    it 'prints the message on the standard output' do
      report = described_class.new
      expect { report.info('gem a 1.0') }
        .to(output("gem a 1.0\n").to_stdout)
    end

    it 'does not fail the check' do
      report = described_class.new
      expect { report.info('gem a 1.0') }
        .not_to(change(report, :status))
    end
  end

  describe '#problem' do
    it 'prints the message on the standard error, after the prefix' do
      report = described_class.new
      expect { report.problem('gem a 1.0 -> 2.0') }
        .to(output("OUTDATED: gem a 1.0 -> 2.0\n").to_stderr)
    end

    it 'prints the prefix it was given' do
      expect { described_class.new('SCORECARD').problem('low') }
        .to(output("SCORECARD: low\n").to_stderr)
    end

    it 'fails the check' do
      report = described_class.new
      expect { report.problem('gem a 1.0 -> 2.0') }
        .to(output.to_stderr.and(change(report, :status).from(0).to(1)))
    end

    it 'counts the problem' do
      report = described_class.new
      expect { report.problem('outdated') }
        .to(output.to_stderr.and(change(report, :problems).by(1)))
    end

    it 'keeps failing the check after several problems' do
      report = described_class.new
      expect { 2.times { report.problem('outdated') } }
        .to(output.to_stderr.and(change(report, :status).from(0).to(1)))
    end
  end

  describe '#problems' do
    it 'is 0 before any problem' do
      expect(described_class.new.problems).to(eq(0))
    end

    it 'counts the problems' do
      report = described_class.new
      expect { 2.times { report.problem('outdated') } }
        .to(output.to_stderr.and(change(report, :problems).from(0).to(2)))
    end
  end

  describe '#compare' do
    it 'prints the version when it is the newest' do
      report = described_class.new
      expect { report.compare('nginx', '1.29.3', '1.29.3') }
        .to(output("nginx 1.29.3\n").to_stdout)
    end

    it 'does not fail the check when the version is the newest' do
      report = described_class.new
      expect { report.compare('nginx', '1.29.3', '1.29.3') }
        .not_to(change(report, :status))
    end

    it 'reports the version and the newest one when they differ' do
      report = described_class.new
      expect { report.compare('nginx', '1.29.2', '1.29.3') }
        .to(output("OUTDATED: nginx 1.29.2 -> 1.29.3\n").to_stderr)
    end

    it 'fails the check when the version is not the newest' do
      report = described_class.new
      expect { report.compare('nginx', '1.29.2', '1.29.3') }
        .to(output.to_stderr.and(change(report, :status).from(0).to(1)))
    end
  end
end
