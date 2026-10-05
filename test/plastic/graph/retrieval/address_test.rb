# frozen_string_literal: true

require_relative "../../../test_helper"
require_relative "../../../../scripts/lib/plastic/graph"

class AddressTest < Minitest::Test
  REVISION = "a" * 64

  def address = Plastic::Graph::Retrieval::Address.new("global")

  def test_a_qualified_reference_escapes_its_path
    assert_equal "plastic://global/1/my%20plan.md?revision=#{REVISION}", address.qualified("1", "my plan.md", REVISION).fetch(:uri)
  end

  def test_a_reference_reads_back_into_its_fields
    fields = address.fields_for("plastic://global/1/my%20plan.md?revision=#{REVISION}")

    assert_equal({ store: "global", intent_id: "1", path: "my plan.md", revision: REVISION }, fields)
  end

  def test_a_reference_with_no_revision_reads_back_with_none
    assert_nil address.fields_for("plastic://global/1/plan.md").fetch(:revision)
  end

  def test_a_malformed_reference_is_refused_by_name
    error = assert_raises(Plastic::Graph::RetrievalGraph::MissingReference) { address.fields_for("broken") }

    assert_equal 'invalid document reference "broken"', error.message
  end

  def test_a_reference_to_another_store_is_refused
    error = assert_raises(Plastic::Graph::RetrievalGraph::MissingReference) { address.verify_store({ store: "other" }) }

    assert_equal "source other is not global", error.message
  end
end
