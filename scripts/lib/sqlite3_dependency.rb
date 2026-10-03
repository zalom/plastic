# frozen_string_literal: true

# Checks whether the installed sqlite3 gem matches Plastic's runtime pin.
module Sqlite3Dependency
  VERSION = "2.9.6"

  module_function

  def available?
    require "sqlite3"
    supported?(SQLite3::VERSION)
  rescue LoadError
    false
  end

  def supported?(version)
    version == VERSION
  end
end
