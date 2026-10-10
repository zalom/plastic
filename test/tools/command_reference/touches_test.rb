# frozen_string_literal: true

require_relative "../../command_reference_helper"

class CommandReferenceTouchesTest < Minitest::Test
  include CommandReferenceHelper

  BOOKKEEPING = %w[changes printed].freeze
  STORE_KEYS = %i[work knowledge references].freeze
  DEFECT = "declaration defect: "
  EXCEPTIONS = {
    read: {
      "intent rule" => "#{DEFECT}it reads the intent without `reads :work`",
      "intent note" => "#{DEFECT}it reads the intent without `reads :work`",
      "intent spec" => "#{DEFECT}it reads intents but declares only :knowledge",
      "intent judge" => "#{DEFECT}it declares nothing but reads the intent",
      "intent revise" => "#{DEFECT}it reads the intent without `reads :work`",
      "intent context" => "#{DEFECT}it reads the intent without `reads :work`"
    },
    write: {
      "backup restore" => "#{DEFECT}it declares only `writes :work` but replaces every database of the store"
    }
  }.freeze

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
    sync = touches("sync up")

    %w[work_graph.db knowledge_graph.db references.db].each do |file|
      assert sync.declared?(file, :write), file
      assert_empty sync.tables_of(file, :write), file
    end
  end

  def test_a_declared_store_is_not_drawn_when_the_scan_found_its_tables
    refute touches("node add").declared?("work_graph.db", :write)
  end

  def test_only_a_command_with_nothing_found_says_no_database_was_found_in_the_code
    refute_includes svg("document get"), "no database found in the code"
    refute_includes svg("next"), "no database found in the code"
    refute_includes svg("version"), "touches no database"
    assert_includes svg("version"), "no database found in the code"
  end

  def test_the_drawing_marks_a_declared_store_and_explains_the_mark_in_its_legend
    assert_includes svg("sync up"), "declared"
    assert_includes svg("sync up"), "R read"
  end

  def test_the_local_database_counts_as_the_work_store
    assert_equal [:work], touches("session note").store_keys(:write)
  end

  def test_the_hooks_read_and_write_what_their_code_names
    assert touches("hook record").writes?("local.db", "locks")
    assert touches("hook record").reads?("work_graph.db", "nodes")
    assert touches("hook end").writes?("local.db", "sessions")
    assert_includes touches("hook resume").store_keys(:read), :work
  end

  def test_the_store_databases_found_equal_the_declared_graphs
    %i[read write].each do |mode|
      CommandReferenceHelper.pages.each do |words, page|
        next if page.kind == :hook

        found = page.touches.store_keys(mode)
        next if found == declared_store_keys(page, mode)

        assert EXCEPTIONS.fetch(mode).fetch(words, nil), "#{words} #{mode}s: found #{found.inspect}, declared #{declared_store_keys(page, mode).inspect}"
      end
    end
  end

  def declared_store_keys(page, mode) = ((mode == :read) ? page.klass.reads : page.klass.writes).uniq.&(STORE_KEYS).sort

  def test_every_exception_is_a_declaration_defect_or_names_a_scan_limit
    EXCEPTIONS.each_value { |group| assert(group.values.all? { |reason| reason.start_with?(DEFECT) || reason.include?("scan limit") }) }
  end
end
