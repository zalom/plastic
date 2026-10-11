# frozen_string_literal: true

require_relative "../../command_reference_helper"

class CommandReferenceTouchesDeclarationTest < Minitest::Test
  include CommandReferenceHelper

  STORE_KEYS = %i[work knowledge references].freeze
  DEFECT = "declaration defect: "
  EXCEPTIONS = {
    read: {
      "intent lock status" => "scan limit: it follows the helper classes of Workflows::Worktree down to Knowledge::Spec"
    },
    write: {}
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
