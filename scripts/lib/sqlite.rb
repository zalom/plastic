# frozen_string_literal: true

require "json"
require "open3"

module Plastic
  module Sqlite
    Error = Class.new(StandardError)

    def self.quote(text)
      "'#{text.gsub("'", "''")}'"
    end

    def self.call(path, sql, readonly: false)
      flags = readonly ? ["-readonly"] : []
      out, err, status = Open3.capture3("sqlite3", "-json", *flags, path, stdin_data: sql)
      raise Error, err.strip unless status.success?

      out.strip.empty? ? [] : JSON.parse(out)
    end
  end
end
