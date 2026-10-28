# typed: false
# frozen_string_literal: true

# The test environment is used exclusively to run your application's
# test suite. You never need to work with it otherwise. Remember that
# your test database is "scratch space" for the test suite and is wiped
# and recreated between test runs. Don't rely on the data there!

Rails.application.configure do
  # Settings specified here will take precedence over those in config/application.rb.

  # While tests run files are not watched, reloading is not necessary.
  config.enable_reloading = false

  # Always eager load: every file in app/ is loaded (and its Sorbet signatures checked) by every run,
  # so the coverage gate also sees files that no example requires.
  config.eager_load = true

  # Configure public file server for tests with cache-control for performance.
  config.public_file_server.headers = { 'cache-control': 'public, max-age=3600' }

  # Show full error reports.
  config.consider_all_requests_local = true
  config.cache_store = :null_store

  # Render exception templates for rescuable exceptions and raise for other exceptions.
  config.action_dispatch.show_exceptions = :rescuable

  # Disable request forgery protection in test environment.
  config.action_controller.allow_forgery_protection = false

  # Deprecations are errors: a deprecated Rails API fails the example that reaches it.
  config.active_support.deprecation = :raise
  config.active_support.disallowed_deprecation = :raise
  config.active_support.disallowed_deprecation_warnings = :all

  # Raises error for missing translations.
  config.i18n.raise_on_missing_translations = true

  # Annotate rendered view with file names.
  # config.action_view.annotate_rendered_view_with_filenames = true

  # Raise error when a before_action's only/except options reference missing actions.
  config.action_controller.raise_on_missing_callback_actions = true
end
