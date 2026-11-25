# frozen_string_literal: true

require_relative "../test_helper"

class FactsTest < Plastic::TestCase
  def facts(values = { name: "ada" }) = Plastic::Facts.new(%i[name mode], values)

  def test_values_for_names_not_declared_are_dropped
    assert_equal({ name: "ada" }, facts(name: "ada", stray: 1).to_h)
  end

  def test_setting_a_declared_fact_keeps_it
    kept = facts.tap { |set| set[:mode] = "auto" }

    assert_equal "auto", kept[:mode]
  end

  def test_setting_an_undeclared_fact_is_invalid
    error = assert_raises(Plastic::Invalid) { facts[:stray] = 1 }

    assert_equal "fact stray is not declared", error.message
  end

  def test_fill_puts_each_value_in_its_placeholder
    assert_equal "hello ada", facts.fill("hello %{name}")
  end

  def test_fill_with_a_missing_value_is_invalid
    error = assert_raises(Plastic::Invalid) { facts.fill("%{name} in %{mode}") }

    assert_equal "no value for mode in \"%{name} in %{mode}\"", error.message
  end

  def test_names_in_lists_the_placeholders_in_order
    assert_equal %i[mode name], Plastic::Facts.names_in("%{mode} then %{name}")
  end

  def test_to_h_is_a_copy
    set = facts
    set.to_h[:name] = "bob"

    assert_equal "ada", set[:name]
  end
end
