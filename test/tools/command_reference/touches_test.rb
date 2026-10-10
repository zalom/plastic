# frozen_string_literal: true

require_relative "../../command_reference_helper"

class CommandReferenceTouchesTest < Minitest::Test
  include CommandReferenceHelper

  BOOKKEEPING = %w[changes printed].freeze

  def touches(words) = page(words).touches

  def svg(words) = CommandReference::Figures::Component.new(page(words)).canvas.standalone

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

  def test_a_private_accessor_behind_a_facade_method_is_followed_to_its_reader
    assert touches("roadmap show").reads?("work_graph.db", "roadmaps")
    assert_includes touches("roadmap show").components.map(&:name), "Retrieval::RoadmapReader"
  end

  def test_a_facade_method_that_builds_a_helper_resolves_to_the_helper_and_not_the_facade_file
    refute touches("intent discover").reads?("local.db", "routine_runs")
    assert_includes touches("roadmap open").components.map(&:name), "Knowledge::Roadmap::ItemOpen"
  end

  def test_an_escaped_update_statement_is_a_write
    assert_equal :write, CommandReference::Touches::Scan.mode_of('batch.add("UPDATE \"locks\" SET x = 1")', "locks")
    assert touches("hook record").writes?("local.db", "locks")
  end

  def test_the_sql_of_a_constant_a_method_uses_is_part_of_the_method
    assert touches("hook record").reads?("work_graph.db", "nodes")
  end

  def test_the_plastic_classes_a_workflow_names_are_components_and_are_scanned
    {
      "intent spec" => "Knowledge::Spec", "intent end" => "Work::Completion::Check", "next" => "Work::NextPick",
      "project links" => "Knowledge::Link::Check", "search" => "Workflows::SearchQuery", "document get" => "Workflows::DocumentLookup"
    }.each { |words, name| assert_includes touches(words).components.map(&:name), name, words }
    assert_includes touches("next").components.map(&:name), "Work::NextOffer"
  end

  def test_a_store_the_command_declares_and_the_scan_misses_is_drawn_from_the_declaration
    node = touches("node done")

    assert node.declared?("work_graph.db", :write)
    assert_empty node.tables_of("work_graph.db", :write)
  end

  def test_a_declared_store_is_not_drawn_when_the_scan_found_its_tables
    refute touches("node add").declared?("work_graph.db", :write)
  end

  def test_a_command_with_a_database_does_not_say_no_database_was_found_in_the_code
    refute_includes svg("document get"), "no database found in the code"
    refute_includes svg("next"), "no database found in the code"
  end

  def test_a_command_with_nothing_found_says_no_database_was_found_in_the_code
    assert_includes svg("version"), "no database found in the code"
    refute_includes svg("version"), "touches no database"
  end

  def test_the_drawing_marks_a_declared_store
    assert_includes svg("node done"), "declared"
  end

  def test_the_drawing_explains_the_mark_in_its_legend
    assert_includes svg("node done"), "R read"
  end

  def test_the_local_database_counts_as_the_work_store
    assert_equal [:work], touches("session note").store_keys(:write)
  end

  def test_a_hook_record_writes_locks_and_reads_nodes
    assert touches("hook record").writes?("local.db", "locks")
    assert touches("hook record").reads?("work_graph.db", "nodes")
  end

  def test_the_hooks_end_and_resume_touch_what_their_code_names
    assert touches("hook end").writes?("local.db", "sessions")
    assert_includes touches("hook resume").store_keys(:read), :work
  end
end
