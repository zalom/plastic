# frozen_string_literal: true

require "json"

require_relative "usage"
require_relative "question"
require_relative "switches"

module SearchCheck
  # The call's arguments: the question file, the field to type, how many intents count and the store folder.
  Arguments = Data.define(:file, :field, :limit, :store) do
    def self.parse(argv, home)
      found = { field: :question, limit: 5, store: File.join(home, "stores", "plastic") }
      files = Switches.new(found).parse(argv)
      raise Usage, "usage: search-check FILE [--keywords] [--limit N] [--store DIR]" unless files.one?

      new(file: files.first, **found)
    end

    def questions
      raise Usage, "no question file at #{file}" unless File.file?(file)

      JSON.parse(File.read(file)).map { |row| Question.from(row) }
    end
  end
end
