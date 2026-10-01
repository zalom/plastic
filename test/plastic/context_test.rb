# frozen_string_literal: true

require_relative "../test_helper"

class ContextTest < Plastic::TestCase
  Graphs = Data.define(:work, :retrieval, :databases)

  def context(declared: %i[id title], facts: { id: "7" }, graphs: {}, session: nil)
    Plastic::Context.new(declared:, facts:, graphs:, session:)
  end

  def test_a_declared_fact_reads_as_a_method
    assert_equal "7", context.id
    assert_nil context.title
  end

  def test_an_undeclared_fact_is_dropped
    assert_equal({ id: "7" }, context(facts: { id: "7", stray: 1 }).facts)
  end

  def test_writing_an_undeclared_fact_raises
    error = assert_raises(Plastic::Invalid) { context[:stray] = 1 }

    assert_equal "fact stray is not declared", error.message
  end

  def test_writing_a_declared_fact_sets_it
    ctx = context
    ctx[:title] = "Kernel"

    assert_equal "Kernel", ctx.title
  end

  def test_facts_are_a_copy
    ctx = context
    ctx.facts[:id] = "8"

    assert_equal "7", ctx.id
  end

  def test_print_keeps_the_lines_in_order
    ctx = context

    assert_same ctx, ctx.print("one")
    ctx.print("two")

    assert_equal %w[one two], ctx.printed
  end

  def test_fill_puts_the_facts_in_the_template
    assert_equal "intent 7", context.fill("intent %{id}")
  end

  def test_fill_refuses_a_fact_with_no_value
    error = assert_raises(Plastic::Invalid) { context.fill("%{id} %{title}") }

    assert_equal "no value for title in \"%{id} %{title}\"", error.message
  end

  def test_a_fact_named_like_a_context_method_raises
    error = assert_raises(Plastic::Invalid) { context(declared: %i[print facts]) }

    assert_equal "fact names print, facts are Context methods", error.message
  end

  def test_the_context_holds_the_graphs_and_the_session
    ctx = context(graphs: Graphs.new(work: :work, retrieval: :retrieval, databases: {}), session: "s-1")

    assert_equal [:work, :retrieval, "s-1"], [ctx.work, ctx.retrieval, ctx.session]
  end
end
