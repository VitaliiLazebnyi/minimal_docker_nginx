# typed: strict
# frozen_string_literal: true

# Copyright (c) 2026 Vitalii Lazebnyi

RSpec.describe(RailsApp::Application) do
  describe 'database configuration (config/database.yml)' do
    # Regression: the production entry had no database, so the first query in production
    # raised instead of opening a SQLite file.
    it 'gives production a SQLite database file under storage/' do
      production = ActiveRecord::Base.configurations.find_db_config('production')
      expect([production.adapter, production.database]).to(eq(['sqlite3', 'storage/production.sqlite3']))
    end

    it 'keeps the test database apart from the production one' do
      expect(ActiveRecord::Base.configurations.find_db_config('test').database).to(eq('storage/test.sqlite3'))
    end
  end
end
