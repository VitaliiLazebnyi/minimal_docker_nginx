# typed: strict

# Bundler vendors connection_pool as Bundler::ConnectionPool, whose fork tracker extends Process while Tapioca
# runs; the generated RBI of sqlite3 (which also extends Process) records that mixin, so Sorbet must know it.
class Bundler::ConnectionPool; end
module Bundler::ConnectionPool::ForkTracker; end
