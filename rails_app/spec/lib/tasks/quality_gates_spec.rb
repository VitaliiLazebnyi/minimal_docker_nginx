# typed: strict
# frozen_string_literal: true

# Copyright (c) 2026 Vitalii Lazebnyi

require_relative '../../../lib/tasks/quality_gates'

RSpec.describe(QualityGates) do
  describe '.run' do
    it 'returns the standard output and error of the command' do
      output, = described_class.run(['sh', '-c', 'echo out; echo err >&2'])
      expect(output).to(eq("out\nerr\n"))
    end

    it 'returns the exit status of the command' do
      _, status = described_class.run(['sh', '-c', 'exit 3'])
      expect(status&.exitstatus).to(eq(3))
    end

    it 'runs the command in the given directory' do
      Dir.mktmpdir do |directory|
        expect(described_class.run(['pwd'], directory:).first).to(eq("#{File.realpath(directory)}\n"))
      end
    end
  end

  describe '.with_file' do
    it 'yields the path of a file with the lines' do
      expect { |block| described_class.with_file(%w[a b], &block) }
        .to(yield_with_args(String))
    end

    it 'writes the lines, one per line' do
      described_class.with_file(%w[show index]) { |path| expect(File.read(path)).to(eq("show\nindex")) }
    end

    it 'deletes the file afterwards' do
      kept = T.let([], T::Array[String])
      described_class.with_file(['a']) { |path| kept << path }
      expect(kept.map { |path| File.exist?(path) }).to(eq([false]))
    end
  end

  describe 'SOURCES' do
    it 'covers the Rakefile, the application and the scripts of the repository' do
      expect(QualityGates::SOURCES).to(eq(['Rakefile', 'app', 'lib', File.expand_path('../../../../script', __dir__)]))
    end
  end
end
