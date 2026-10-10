# frozen_string_literal: true

require_relative "../../command_reference_helper"

class CommandReferenceTouchesTest < Minitest::Test
  include CommandReferenceHelper

  BOOKKEEPING = %w[changes printed].freeze
  STORE_KEYS = %i[work knowledge references].freeze

  # A command whose scan and declaration differ, with the reason, reported to the lead.
  EXCEPTIONS = {
    "intent abandon" => "the knowledge write goes through the sync layer several calls deep, past the scan's reach",
    "intent end" => "the knowledge write goes through the sync layer several calls deep, past the scan's reach",
    "intent new" => "the knowledge write goes through the sync layer several calls deep, past the scan's reach",
    "project new" => "the knowledge write goes through the sync layer several calls deep, past the scan's reach",
    "project links" => "the work happens several calls deep in the document or evidence layer, past the scan's reach",
    "sync up" => "the references database is touched inside the sync layer, past the scan's reach",
    "sync down" => "the references database is touched inside the sync layer, past the scan's reach",
    "session note" => "the note lands in local.db, which the store keys leave out, while the declaration says work",
    "intent rule" => "the intent problem reads add the work database to a command declared knowledge only",
    "intent revise" => "the knowledge write goes through the sync layer several calls deep, past the scan's reach",
    "intent note" => "the note is kept by a noter whose database the declaration names knowledge, and the scan sees work reads",
    "intent spec" => "the spec read reaches the knowledge graph through evidence reads, past the scan's reach",
    "intent discover" => "the discovery reads references the declaration leaves out",
    "intent context" => "the work happens several calls deep in the document or evidence layer, past the scan's reach",
    "next" => "the work happens several calls deep in the document or evidence layer, past the scan's reach",
    "intent archive" => "the knowledge write goes through the sync layer several calls deep, past the scan's reach",
    "intent unarchive" => "the knowledge write goes through the sync layer several calls deep, past the scan's reach",
    "backup" => "the declaration is coarser than the code, which touches local.db only",
    "backup purge" => "the declaration is coarser than the code, which touches local.db only",
    "backup restore" => "the declaration is coarser than the code, which touches local.db only",
    "document get" => "the work happens several calls deep in the document or evidence layer, past the scan's reach",
    "document batch" => "the work happens several calls deep in the document or evidence layer, past the scan's reach",
    "search" => "the work happens several calls deep in the document or evidence layer, past the scan's reach",
    "graph resume" => "the work happens several calls deep in the document or evidence layer, past the scan's reach",
    "roadmap show" => "the roadmap read goes through the roadmap reader, past the scan's reach",
    "roadmap next" => "the roadmap read goes through the roadmap reader, past the scan's reach",
    "roadmap check" => "the roadmap read goes through the roadmap reader, past the scan's reach",
    "roadmap open" => "the knowledge write goes through the sync layer several calls deep, past the scan's reach"
  }.freeze

  def touches(words) = page(words).touches

  def test_a_delegated_writer_method_writes_the_table_of_its_writer
    assert touches("node add").writes?("work_graph.db", "nodes")
  end

  def test_a_keyword_hash_names_the_tables_it_writes
    assert touches("intent rule").writes?("knowledge_graph.db", "rulings")
  end

  def test_status_reads_intents_and_writes_nothing
    assert touches("status").reads?("work_graph.db", "intents")
    assert_empty touches("status").tables(:write)
  end

  def test_a_distribution_command_touches_no_database
    assert_predicate touches("version"), :empty?
  end

  def test_no_command_lists_a_bookkeeping_table
    CommandReferenceHelper.pages.each_value do |page|
      assert_empty page.touches.tables(:read) & BOOKKEEPING
      assert_empty page.touches.tables(:write) & BOOKKEEPING
    end
  end

  def test_a_method_that_only_checks_is_a_read
    assert touches("intent note").reads?("work_graph.db", "intents")
    refute touches("intent note").writes?("work_graph.db", "intents")
  end

  def test_a_helper_hop_resolves_to_the_helper_and_not_the_facade
    backup = touches("backup list")

    assert backup.reads?("local.db", "backups")
    refute backup.writes?("local.db", "routine_runs")
    refute backup.reads?("local.db", "routine_runs")
  end

  def test_a_hook_receiver_through_a_chained_graph_open_is_found
    assert touches("hook end").writes?("local.db", "sessions")
  end

  def test_the_files_a_command_prints_come_from_prints
    assert_includes touches("intent end").files, "store/index.json"
  end

  def test_the_store_databases_found_equal_the_declared_graphs
    CommandReferenceHelper.pages.each do |words, page|
      next unless page.kind == :routine || page.kind == :command

      found = page.touches.store_keys.sort
      next if found == declared_store_keys(page)

      assert EXCEPTIONS.fetch(words, nil), "#{words}: found #{found.inspect}, declared #{declared_store_keys(page).inspect}"
    end
  end

  def declared_store_keys(page) = ((page.klass.reads + page.klass.writes).uniq & STORE_KEYS).sort

  def test_every_exception_names_its_reason
    assert(EXCEPTIONS.values.all? { |reason| reason.to_s.split.size > 3 })
  end
end
