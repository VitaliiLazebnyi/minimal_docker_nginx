# typed: strict
# frozen_string_literal: true

# Copyright (c) 2026 Vitalii Lazebnyi

require_relative '../../../../lib/tasks/quality_gates'

RSpec.describe(QualityGates::Complexity) do
  describe '.complex_methods' do
    sig { returns(String) }
    let(:report) do
      <<~FLOG
        248.2: flog total
            5.9: flog/method average

            20.0: Simple#method                  app/simple.rb:3-9
            20.1: Complex#method                 app/complex.rb:3-40
            31.5: Other#method                   ../script/other.rb:1-30
            9.5: main#none
      FLOG
    end

    it 'lists the methods scoring above the threshold, with their score' do
      expect(described_class.complex_methods(report)).to(eq(['20.1: Complex#method', '31.5: Other#method']))
    end
  end

  describe '.score' do
    it 'returns the score of a method line' do
      expect(described_class.score('   20.1: Complex#method   app/complex.rb:3-40')).to(be(20.1))
    end
  end
end
