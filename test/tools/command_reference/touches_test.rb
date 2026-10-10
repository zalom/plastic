# frozen_string_literal: true

require_relative "../../command_reference_helper"

class CommandReferenceTouchesTest < Minitest::Test
  include CommandReferenceHelper

  BOOKKEEPING = %w[changes printed].freeze
  STORE_KEYS = %i[work knowledge references].freeze

  # A command whose scan and declaration differ, with the reason, reported to the lead.
  EXCEPTIONS = {}.freeze

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
    refute touches("intent note").writes?("work_graph.db", "intents") && touches("intent note").components.none? { |part| part.name.include?("Noter") }
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

      declared = (page.klass.reads + page.klass.writes).uniq & STORE_KEYS
      found = page.touches.store_keys.sort
      next if found == declared.sort

      assert EXCEPTIONS.fetch(words, nil), "#{words}: found #{found.inspect}, declared #{declared.sort.inspect}"
    end
  end

  def test_every_exception_names_its_reason
    assert(EXCEPTIONS.values.all? { |reason| reason.to_s.split.size > 3 })
  end
end
