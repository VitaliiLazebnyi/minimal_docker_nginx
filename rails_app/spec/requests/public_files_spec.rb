# typed: false
# frozen_string_literal: true

RSpec.describe 'GET /robots.txt' do
  # Regression: an autocorrection had turned the header names of config.public_file_server.headers into
  # symbols, which Rack does not send; header names are strings.
  it 'serves the static file with the configured cache-control header' do
    get '/robots.txt'
    expect([response.status, response.headers['cache-control']]).to eq([200, 'public, max-age=3600'])
  end
end
