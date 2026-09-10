# encoding: UTF-8
# frozen_string_literal: true

require "minitest/autorun"
require "yaml"

require_relative "../scripts/lib/node_return"

# NodeReturn (intent 340, G7, n4): the closed return schema. Matrix rows
# 4.1-4.12, 4.37, 4.38 in nodes/n4.md.
class NodeReturnTest < Minitest::Test
  # --- 4.1: the happy path -----------------------------------------------------

  def test_valid_return_parses
    result = NodeReturn.parse(<<~YAML)
      node: n4
      status: done
      commit: abc1234
      summary: landed the schema and the gate
      findings:
        - a durable discovery
    YAML

    assert result.ok
    assert_equal "n4", result.node
    assert_equal "done", result.status
    assert_equal "abc1234", result.commit
    assert_equal ["a durable discovery"], result.findings
    assert_empty result.errors
  end

  # --- 4.2: not YAML at all ----------------------------------------------------

  def test_non_yaml_is_return_unparsable
    result = NodeReturn.parse("node: n4\nstatus: [unterminated flow sequence\n")

    refute result.ok
    refute_empty result.errors
  end

  # --- 4.3: YAML that parses but is not a mapping ------------------------------

  def test_non_mapping_is_return_unparsable
    result = NodeReturn.parse("- one\n- two\n- three\n")

    refute result.ok
    refute_empty result.errors
  end

  # --- 4.4: an unknown key ------------------------------------------------------

  def test_unknown_key_is_refused
    result = NodeReturn.parse(<<~YAML)
      node: n4
      status: done
      commit: abc1234
      made_up_field: true
    YAML

    refute result.ok
    assert(result.errors.any? { |e| e.include?("made_up_field") })
  end

  # --- 4.5: an unknown status ----------------------------------------------------

  def test_unknown_status_is_refused
    result = NodeReturn.parse(<<~YAML)
      node: n4
      status: finished
      commit: abc1234
    YAML

    refute result.ok
    assert(result.errors.any? { |e| e.include?("status") })
  end

  # --- 4.6: done requires commit -------------------------------------------------

  def test_done_without_commit_is_refused
    result = NodeReturn.parse(<<~YAML)
      node: n4
      status: done
      summary: no commit named
    YAML

    refute result.ok
    assert(result.errors.any? { |e| e.include?("commit") })
  end

  # --- 4.7: needs_decision requires question -------------------------------------

  def test_needs_decision_without_question_is_refused
    result = NodeReturn.parse(<<~YAML)
      node: n4
      status: needs_decision
    YAML

    refute result.ok
    assert(result.errors.any? { |e| e.include?("question") })
  end

  # --- 4.8: failed_verification and blocked require reason -----------------------

  def test_failure_without_reason_is_refused
    %w[failed_verification blocked].each do |status|
      result = NodeReturn.parse("node: n4\nstatus: #{status}\n")

      refute result.ok, "#{status} without reason must be refused"
      assert(result.errors.any? { |e| e.include?("reason") })
    end
  end

  # --- 4.9: node mismatch is a RunnerAbsorb-level check, not NodeReturn's own ----
  # (NodeReturn.parse never receives the dispatched node id; it only proves the
  # field itself is present and well-formed.)

  def test_node_mismatch_is_refused
    result = NodeReturn.parse(<<~YAML)
      node: n9
      status: done
      commit: abc1234
    YAML

    assert result.ok
    assert_equal "n9", result.node
  end

  # --- 4.10: findings coerced to strings and capped -------------------------------

  def test_findings_are_coerced_and_capped
    long_finding = "x" * 900
    raw_findings = [long_finding] + (1..25).map { |i| i.even? ? i : { "nested" => i } }
    doc = { "node" => "n4", "status" => "done", "commit" => "abc1234", "findings" => raw_findings }

    result = NodeReturn.parse(YAML.dump(doc))

    assert result.ok
    assert result.findings.length <= NodeReturn::MAX_FINDINGS
    assert result.findings.all? { |f| f.is_a?(String) }
    assert result.findings.all? { |f| f.length <= NodeReturn::MAX_FINDING_LENGTH }
    assert result.findings.any? { |f| f.length == NodeReturn::MAX_FINDING_LENGTH }
  end

  # --- 4.11: alias / anchor bomb --------------------------------------------------

  def test_aliases_are_refused
    bomb = <<~YAML
      node: n4
      status: done
      commit: abc1234
      summary: &a ["x","x","x","x","x","x","x","x","x","x"]
      findings: [*a,*a,*a,*a,*a,*a,*a,*a,*a,*a]
    YAML

    result = NodeReturn.parse(bomb)

    refute result.ok
    refute_empty result.errors
  end

  # --- 4.12: invalid UTF-8 never raises --------------------------------------------

  def test_invalid_utf8_does_not_raise
    bad = (+"node: n4\nstatus: done\ncommit: abc1234\nsummary: \xFF\xFE broken\n").force_encoding("ASCII-8BIT")

    result = nil
    assert_silent_of_raise { result = NodeReturn.parse(bad) }

    refute_nil result
    assert result.ok, "a scrubbed invalid byte must not stop an otherwise valid return from parsing"
  end

  # --- 4.37: a malformed proposed_nodes entry --------------------------------------

  def test_malformed_proposed_node_entry_is_refused
    result = NodeReturn.parse(YAML_HEADER + <<~YAML)
      proposed_nodes:
        - "just a string, not a mapping"
    YAML

    refute result.ok
    assert(result.errors.any? { |e| e.include?("proposed_nodes") })

    result2 = NodeReturn.parse(YAML_HEADER + <<~YAML)
      proposed_nodes:
        - kind: work
          title: missing needs
    YAML

    refute result2.ok
    assert(result2.errors.any? { |e| e.include?("needs") })
  end

  # --- 4.38: a malformed proposed_edges entry --------------------------------------

  def test_malformed_proposed_edge_entry_is_refused
    result = NodeReturn.parse(YAML_HEADER + <<~YAML)
      proposed_edges:
        - "not a mapping either"
    YAML

    refute result.ok
    assert(result.errors.any? { |e| e.include?("proposed_edges") })

    result2 = NodeReturn.parse(YAML_HEADER + <<~YAML)
      proposed_edges:
        - from: n4
    YAML

    refute result2.ok
    assert(result2.errors.any? { |e| e.include?("to") })
  end

  # --- well-formed proposed_nodes / proposed_edges pass through --------------------

  def test_well_formed_proposals_are_normalized
    result = NodeReturn.parse(YAML_HEADER + <<~YAML)
      proposed_nodes:
        - kind: work
          title: a follow-up
          needs: [n4]
          files: [scripts/lib/foo.rb]
          budget: 50000
      proposed_edges:
        - from: n4
          to: n8
    YAML

    assert result.ok
    assert_equal 1, result.proposed_nodes.length
    assert_equal "work", result.proposed_nodes.first["kind"]
    assert_equal ["n4"], result.proposed_nodes.first["needs"]
    assert_equal 1, result.proposed_edges.length
    assert_equal "n8", result.proposed_edges.first["to"]
  end

  YAML_HEADER = "node: n4\nstatus: done\ncommit: abc1234\n"

  def assert_silent_of_raise
    yield
  rescue StandardError => e
    flunk "expected no exception, got #{e.class}: #{e.message}"
  end
end
