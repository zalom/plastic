# frozen_string_literal: true

require "json"
require "optparse"
require "sqlite3"
require_relative "../lib/plastic/graph/retrieval/search"

# Runs a file of known questions through Plastic's own search class against a store and reports, for each question,
# the rank of the first known answer among the first intents returned. Exact: no model call. The store opens
# read-only, with no migration and no schema prepare, so a run writes nothing.
module SearchCheck
  # A call that cannot run: the file or the store is missing, or an option is wrong.
  class Usage < StandardError; end

  # The knowledge and retrieval files of one store, opened read-only. It answers the two calls Search makes of a store.
  class ReadOnlyStore
    KNOWLEDGE = "knowledge_graph.db"
    RETRIEVAL = "retrieval_graph.db"

    def initialize(folder)
      files = [KNOWLEDGE, RETRIEVAL].map { |name| File.join(folder, name) }
      raise Usage, "no store at #{folder}" unless files.all? { |file| File.file?(file) }

      @connection = SQLite3::Database.new(files.first, readonly: true, results_as_hash: true)
      @connection.execute("ATTACH ? AS retrieval", files.last)
    end

    def retrieval_present? = true

    def rows(sql, **binds) = @connection.execute(sql, binds)

    # The one origin whose documents the store holds.
    def origin_id = self.class.single(rows("SELECT DISTINCT origin_id FROM document_heads").map { |row| row.fetch("origin_id") })

    def self.single(ids) = ids.one? ? ids.first : raise(Usage, "the store holds #{ids.size} origins, not one")
  end

  # One known question: what to type and which intents hold the answer.
  Question = Data.define(:id, :question, :keywords, :answers) do
    def self.from(row) = new(row.fetch("id"), row.fetch("question"), row.fetch("keywords", ""), row.fetch("answers"))

    def line(rank) = format("%-6s %-14s %s", id, rank ? "hit  rank #{rank}" : "miss", question)
  end

  # Reads the options of a call into the hash it is given.
  class Switches
    def initialize(found)
      @found = found
    end

    def parse(argv) = parser.parse(argv)

    private

    def parser
      OptionParser.new.tap do |parser|
        parser.on("--keywords") { @found[:field] = :keywords }
        parser.on("--limit N", Integer) { |number| @found[:limit] = number }
        parser.on("--store DIR") { |folder| @found[:store] = folder }
      end
    end
  end

  # The call's arguments: the question file, the field to type, how many intents count and the store folder.
  Arguments = Data.define(:file, :field, :limit, :store) do
    def self.parse(argv, home)
      found = { field: :question, limit: 5, store: File.join(home, "stores", "plastic") }
      files = Switches.new(found).parse(argv)
      raise Usage, "usage: search-check FILE [--keywords] [--limit N] [--store DIR]" unless files.one?

      new(files.first, **found)
    end

    def questions
      raise Usage, "no question file at #{file}" unless File.file?(file)

      JSON.parse(File.read(file)).map { |row| Question.from(row) }
    end
  end

  # The rank of the first known answer among the first `limit` intents a search returns, or nil.
  class Ranker
    def initialize(store, limit)
      @search = Plastic::Graph::Retrieval::Search.new(store, origin: Struct.new(:id).new(store.origin_id))
      @limit = limit
    end

    def call(answers, terms) = intents(terms).index { |id| answers.include?(id) }&.+(1)

    private

    attr_reader :search, :limit

    def intents(terms)
      hits = search.call(terms, limit: Plastic::Graph::Retrieval::Search::SEARCH_LIMIT)
      hits.map { |hit| hit.fetch("intent_id") }.uniq.first(limit)
    rescue Plastic::Graph::RetrievalGraph::InvalidSearch
      []
    end
  end

  # The report lines of a run: one for each question and a total.
  class Check
    def initialize(arguments, questions)
      @questions = questions
      @limit = arguments.limit
      @terms = ->(question) { question.public_send(arguments.field) }
      @ranker = Ranker.new(ReadOnlyStore.new(arguments.store), @limit)
    end

    def lines
      ranks = @questions.map { |question| @ranker.call(question.answers, @terms.call(question)) }
      [*@questions.zip(ranks).map { |question, rank| question.line(rank) }, "total #{ranks.compact.size}/#{ranks.size} in the first #{@limit}"]
    end
  end

  # Runs every question and prints one line each and a total. Exit 0 ran, 2 called wrongly.
  class CLI
    def initialize(argv, out:, err:, home:)
      @argv = argv
      @home = home
      @streams = [out, err]
    end

    def call
      arguments = Arguments.parse(@argv, @home)
      report(arguments, arguments.questions)
      0
    rescue Usage, OptionParser::ParseError => error
      @streams.last.puts "search-check: #{error.message}"
      2
    end

    private

    def report(arguments, questions) = @streams.first.puts(Check.new(arguments, questions).lines)
  end
end
