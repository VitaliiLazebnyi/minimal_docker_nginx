# typed: false
# frozen_string_literal: true

RSpec.describe HealthController do
  describe 'GET /health' do
    before { get '/health' }

    it 'answers 200 OK' do
      expect(response).to have_http_status(:ok)
    end

    it 'answers with JSON' do
      expect(response.media_type).to eq('application/json')
    end

    it 'reports the status OK, which the Docker HEALTHCHECK looks for' do
      expect(response.body).to eq('{"status":"OK"}')
    end
  end

  describe 'HEAD /health' do
    it 'answers 200 OK without a body' do
      head '/health'
      expect([response.status, response.body]).to eq([200, ''])
    end
  end
end
