require 'rails_helper'

RSpec.describe 'Health Endpoint', type: :request do
  describe 'GET /health' do
    it 'returns a 200 OK status and correct JSON' do
      get '/health'

      expect(response).to have_http_status(:ok)
      json_response = JSON.parse(response.body)
      expect(json_response).to eq({ 'status' => 'OK' })
    end
  end
end
