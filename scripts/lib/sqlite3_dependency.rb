# frozen_string_literal: true

require_relative "plastic/graph/database/sqlite_loader"

# Checks whether the installed sqlite3 gem matches Plastic's runtime pin.
module Sqlite3Dependency
  module_function

  def available?
    require "sqlite3"
    supported?(SQLite3::VERSION)
  rescue LoadError
    false
  end

  def supported?(version)
    version == Plastic::Graph::Database::SqliteLoader::VERSION
  end
end
