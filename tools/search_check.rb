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
    def origin_id
      ids = rows("SELECT DISTINCT origin_id FROM document_heads").map { |row| row.fetch("origin_id") }
      raise Usage, "the store holds #{ids.size} origins, not one" unless ids.one?

      ids.first
    end
  end

  # One known question: what to type and which intents hold the answer.
  Question = Data.define(:id, :question, :keywords, :answers) do
    def self.from(row) = new(row.fetch("id"), row.fetch("question"), row.fetch("keywords", ""), row.fetch("answers"))

    def terms(by_keywords) = by_keywords ? keywords : question
  end

  # The rank of the first known answer among the first `limit` intents a search returns, or nil.
  class Ranker
    def initialize(store, limit)
      @search = Plastic::Graph::Retrieval::Search.new(store, origin: Struct.new(:id).new(store.origin_id))
      @limit = limit
    end

    def call(question, terms)
      first = intents(terms)
      first.index { |id| question.answers.include?(id) }&.+(1)
    end

    private

    attr_reader :search, :limit

    def intents(terms)
      hits = search.call(terms, limit: Plastic::Graph::Retrieval::Search::SEARCH_LIMIT)
      hits.map { |hit| hit.fetch("intent_id") }.uniq.first(limit)
    rescue Plastic::Graph::RetrievalGraph::InvalidSearch
      []
    end
  end

  # Reads the arguments, runs every question and prints one line each and a total. Exit 0 ran, 2 called wrongly.
  class CLI
    def initialize(argv, out:, err:, home:)
      @argv = argv.dup
      @out = out
      @err = err
      @home = home
      @options = { keywords: false, limit: 5, store: File.join(home, "stores", "plastic") }
    end

    def call
      file = parse
      report(questions(file))
      0
    rescue Usage, OptionParser::ParseError => error
      @err.puts "search-check: #{error.message}"
      2
    end

    private

    def parse
      parser.parse!(@argv)
      raise Usage, "usage: search-check FILE [--keywords] [--limit N] [--store DIR]" unless @argv.one?

      @argv.first
    end

    def parser
      OptionParser.new do |opts|
        opts.on("--keywords") { @options[:keywords] = true }
        opts.on("--limit N", Integer) { |number| @options[:limit] = number }
        opts.on("--store DIR") { |folder| @options[:store] = folder }
      end
    end

    def questions(file)
      raise Usage, "no question file at #{file}" unless File.file?(file)

      JSON.parse(File.read(file)).map { |row| Question.from(row) }
    end

    def report(questions)
      ranker = Ranker.new(ReadOnlyStore.new(@options[:store]), @options[:limit])
      ranks = questions.map { |question| [question, ranker.call(question, question.terms(@options[:keywords]))] }
      ranks.each { |question, rank| @out.puts line(question, rank) }
      @out.puts "total #{ranks.count { |_, rank| rank }}/#{ranks.size} in the first #{@options[:limit]}"
    end

    def line(question, rank)
      status = rank ? "hit  rank #{rank}" : "miss"
      format("%-6s %-14s %s", question.id, status, question.question)
    end
  end
end
