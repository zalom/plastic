# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../../lib/plastic/workflows/store_names"

# The stores a call names with --stores, and the command it offers for another store.
class StoreNamesTest < Plastic::TestCase
  Scope = Struct.new(:slug, :projects, :requested) do
    def requested? = requested
  end
  Context = Struct.new(:stores, :scope)

  def names = Object.new.extend(Plastic::Workflows::StoreNames)

  def scope(requested: false) = Scope.new("global", { "blog" => {} }, requested)

  def test_no_stores_named_reads_the_call_s_own_store
    assert_equal ["global"], names.store_slugs(Context.new(nil, scope))
  end

  def test_named_stores_are_read_once_each_in_the_order_named
    assert_equal %w[blog global], names.store_slugs(Context.new(" blog, global,blog", scope))
  end

  def test_an_empty_list_is_a_usage_error
    assert_equal "name at least one store after --stores", assert_raises(Plastic::Usage) { names.store_slugs(Context.new(",", scope)) }.message
  end

  def test_an_unregistered_store_is_a_usage_error
    assert_match(/no registered project named "shop"; the projects are blog/, assert_raises(Plastic::Usage) { names.store_slugs(Context.new("shop", scope)) }.message)
  end

  def test_stores_with_a_project_is_a_usage_error
    assert_raises(Plastic::Usage) { names.refuse_project(Context.new("blog", scope(requested: true))) }
  end

  def test_a_command_for_another_store_carries_its_project
    assert_equal ["plastic intent auto 1 --project blog", "plastic intent auto 1", "plastic x --project shop"],
      [names.in_store(scope, "plastic intent auto 1", "blog"), names.in_store(scope, "plastic intent auto 1", "global"), names.in_store(scope, "plastic x --project shop", "blog")]
  end
end
