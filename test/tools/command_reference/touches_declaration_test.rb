# frozen_string_literal: true

require_relative "../../command_reference_helper"

class CommandReferenceTouchesDeclarationTest < Minitest::Test
  include CommandReferenceHelper

  STORE_KEYS = %i[work knowledge references].freeze
  DEFECT = "declaration defect: "
  EXCEPTIONS = {
    read: {
      "project links" => "#{DEFECT}it reads intents through Link::Check (link/check.rb:40) without `reads :work`",
      "intent rule" => "#{DEFECT}it reads the intent (add_ruling.rb:15) without `reads :work`",
      "intent note" => "#{DEFECT}it reads the intent (note_intent.rb:14) without `reads :work`",
      "intent judge" => "#{DEFECT}it declares nothing but reads the intent (prepare_judge.rb:16)",
      "intent spec" => "#{DEFECT}it reads the intent (show_spec.rb:22) but declares only :knowledge",
      "intent link" => "#{DEFECT}it reads the intent (add_link.rb:15) without `reads :work`",
      "backup list" => "#{DEFECT}it declares nothing but reads the backups table (store_backups.rb:36)",
      "intent approve" => "#{DEFECT}it reads the spec document (approve_intent.rb:22) without `reads :knowledge`",
      "node add" => "#{DEFECT}it reads the spec document (add_node.rb:33) without `reads :knowledge`",
      "intent lock status" => "scan limit: it follows the helper classes of Workflows::Worktree down to Knowledge::Spec",
      "auto" => "#{DEFECT}it reads the spec document (start_auto.rb:34) without `reads :knowledge`"
    },
    write: {
      "auto" => "#{DEFECT}it activates the intent, which writes its document (intent/writer.rb), without `writes :knowledge`"
    }
  }.freeze

  def test_the_store_databases_found_are_declared_or_a_listed_exception_and_declared_ones_are_drawn
    %i[read write].each do |mode|
      CommandReferenceHelper.pages.each do |words, page|
        next if page.kind == :hook

        extra = page.touches.store_keys(mode) - declared_store_keys(page, mode)
        assert EXCEPTIONS.fetch(mode).key?(words), "#{words} #{mode}s undeclared #{extra.inspect}" unless extra.empty?

        assert_empty undrawn(page, mode), "#{words} #{mode}s declared and not drawn"
      end
    end
  end

  def test_an_exception_is_listed_only_while_the_scan_still_finds_the_extra_store
    EXCEPTIONS.each do |mode, group|
      group.each_key do |words|
        page = CommandReferenceHelper.pages.fetch(words)

        refute_empty page.touches.store_keys(mode) - declared_store_keys(page, mode), "#{words} #{mode}"
      end
    end
  end

  def test_a_helper_class_that_is_one_of_the_scanned_files_is_not_listed_again
    source = CommandReferenceHelper.model.source
    spec = "scripts/lib/plastic/graph/knowledge/spec.rb"
    helpers = CommandReference::Touches::Helpers.new(source)

    assert_includes helpers.call(["scripts/lib/plastic/workflows/show_spec.rb"]).map(&:file), spec
    refute_includes helpers.call(["scripts/lib/plastic/workflows/show_spec.rb", spec]).map(&:file), spec
  end

  def declared_store_keys(page, mode)
    declared = (mode == :read) ? page.klass.reads + page.klass.writes : page.klass.writes
    declared.uniq.&(STORE_KEYS).sort
  end

  def undrawn(page, mode)
    own = (mode == :read) ? page.klass.reads : page.klass.writes
    own.uniq.&(STORE_KEYS).sort - page.touches.store_keys(mode)
  end

  def test_every_exception_is_a_declaration_defect_or_names_a_scan_limit
    EXCEPTIONS.each_value { |group| assert(group.values.all? { |reason| reason.start_with?(DEFECT) || reason.include?("scan limit") }) }
  end
end
