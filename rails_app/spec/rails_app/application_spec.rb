# typed: false
# frozen_string_literal: true

RSpec.describe RailsApp::Application do
  describe 'database configuration (config/database.yml)' do
    subject(:configuration) do
      ActiveRecord::DatabaseConfigurations.new(Rails.application.config.database_configuration)
    end

    # Regression: the production entry had no database, so the first query in production
    # raised instead of opening a SQLite file.
    it 'gives production a SQLite database file under storage/' do
      production = configuration.find_db_config('production')
      expect([production.adapter, production.database]).to eq(['sqlite3', 'storage/production.sqlite3'])
    end

    it 'keeps the test database apart from the production one' do
      expect(configuration.find_db_config('test').database).to eq('storage/test.sqlite3')
    end
  end
end
