# typed: strict
# frozen_string_literal: true

# Copyright (c) 2026 Vitalii Lazebnyi

require_relative '../../../../script/outdated/nginx'
require_relative '../../support/script_repository'

RSpec.describe(Outdated::Nginx) do
  sig { returns(String) }
  let(:root) { Dir.mktmpdir }

  sig { returns(Outdated::Report) }
  let(:report) { Outdated::Report.new }

  after { FileUtils.remove_entry(root) }

  before do
    ScriptRepository.install(self, root, ['Dockerfile', "ARG NGINX_VERSION=1.29.3\n"])
    tags = [%w[release-1.29.3 a], %w[release-1.29.10 b], %w[release-1.31.0-rc1 c], %w[v2.0.0 d]].to_h
    allow(Outdated::GitTags).to(receive(:of).with('https://github.com/nginx/nginx').and_return(tags))
    allow(report).to(receive(:compare))
  end

  describe '#check' do
    it 'compares the nginx release of the Dockerfile with the newest release tag of nginx' do
      described_class.new(report).check
      expect(report).to(have_received(:compare).with('nginx (Dockerfile ARG NGINX_VERSION)', '1.29.3', '1.29.10'))
    end
  end
end
