# encoding: UTF-8
# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "time"

require_relative "../scripts/lib/node_ledger"
require_relative "../scripts/lib/runner_policy"
require_relative "../scripts/lib/agent_models"
require_relative "../scripts/lib/graph_measure_models"

# GraphMeasureModelsTest (intent 343, G10, n5): the store walk and the model
# comparison half of `graph-measure cohorts`. Matrix rows 5.1-5.13 in
# nodes/n5.md; the subprocess and install-sync rows (5.14-5.16) live in
# test/graph_measure_cli_test.rb and test/install_sync_test.rb.
#
# Rows 5.8 and 5.10 read the two real ledger fixtures (337, 340) copied into
# a synthetic store dir, never authored by this test (spec D18's rule the
# other way round: a case a real ledger DOES produce is checked against that
# real ledger). Every other row builds its own hermetic store in a
# Dir.mktmpdir.
class GraphMeasureModelsTest < Minitest::Test
  FIXTURES = File.expand_path("fixtures/ledgers", __dir__)
  DIR_337 = File.join(FIXTURES, "337--roadmap-graph")
  DIR_340 = File.join(FIXTURES, "340--runner-core-in-session")

  RUNNING = { holder: "auto-1", expires: "2099-01-01T00:00:00Z", packet: "abc123" }.freeze

  def with_store_dir
    Dir.mktmpdir("graph-measure-models-test") { |dir| yield dir }
  end

  def stamp(str)
    Time.iso8601(str)
  end

  def stage(ts, subject, text)
    "#{ts}  #{subject}  #{text}\n"
  end

  def transition(ts, subject, state, fields: {}, comment: nil)
    NodeLedger.transition_line(subject: subject, state: state, fields: fields, comment: comment, now: stamp(ts))
  end

  # One running line then one terminal line for `id`, both carrying `model:`
  # (spec D6's dispatch shape: `running` requires model=, `done` merely
  # accepts it).
  def node_transitions(id, model, terminal: "done")
    [
      transition("2026-01-01T09:00:00Z", id, "running", fields: RUNNING.merge(model: model)),
      transition("2026-01-01T09:10:00Z", id, terminal, fields: RUNNING.merge(model: model, gates: "suite", commit: "abc1234")),
    ]
  end

  def write_node_file(dir, id, kind)
    FileUtils.mkdir_p(File.join(dir, "nodes"))
    File.write(File.join(dir, "nodes", "#{id}.md"), <<~MD)
      ---
      node: #{id}
      kind: #{kind}
      files: []
      ---
      # #{id}
      body
    MD
  end

  def write_intent(store, id, transitions: [], node_kinds: {}, extra_lines: [])
    dir = File.join(store, id)
    FileUtils.mkdir_p(dir)
    content = (Array(transitions).flatten + Array(extra_lines)).join
    File.write(File.join(dir, "savepoint.md"), content)
    node_kinds.each { |nid, kind| write_node_file(dir, nid, kind) }
    dir
  end

  # --- 5.1: every intent with a savepoint.md is walked -------------------------

  def test_every_intent_with_a_savepoint_is_read
    with_store_dir do |store|
      write_intent(store, "1--alpha", transitions: node_transitions("n1", "sonnet"), node_kinds: { "n1" => "work" })
      write_intent(store, "2--beta", transitions: node_transitions("v1", "opus"), node_kinds: { "v1" => "verify" })

      record = GraphMeasureModels.read(store)
      assert_equal 2, record[:population][:with_savepoint]
      intents = record[:node_rows].map { |r| r[:intent] }.uniq.sort
      assert_equal %w[1--alpha 2--beta], intents
    end
  end

  # --- 5.2: an intent with no savepoint.md is skipped and counted, never errors --

  def test_intent_without_savepoint_is_skipped_and_counted
    with_store_dir do |store|
      FileUtils.mkdir_p(File.join(store, "1--not-started"))
      write_intent(store, "2--ok", transitions: node_transitions("n1", "sonnet"), node_kinds: { "n1" => "work" })

      record = GraphMeasureModels.read(store)
      assert_equal 2, record[:population][:total]
      assert_equal 1, record[:population][:with_savepoint]
      assert_equal 1, record[:population][:without_savepoint]
    end
  end

  # --- 5.3: the qualified population is reported per field, not averaged -------

  def test_qualified_population_reported_per_field
    with_store_dir do |store|
      write_intent(store, "1--full",
                   transitions: node_transitions("n1", "sonnet"),
                   node_kinds: { "n1" => "work" },
                   extra_lines: [stage("2026-01-01T09:20:00Z", "Done", "delivered")])
      write_intent(store, "2--old",
                   transitions: [transition("2026-01-01T09:00:00Z", "n1", "done",
                                             fields: { holder: "auto-2", gates: "suite", commit: "def5678" })],
                   extra_lines: [stage("2026-01-01T09:05:00Z", "Done", "delivered")])
      write_intent(store, "3--nothing",
                   extra_lines: [stage("2026-01-01T09:00:00Z", "What", "spec.md created")])

      record = GraphMeasureModels.read(store)
      assert_equal 3, record[:population][:with_savepoint]
      assert_equal 2, record[:qualified][:done], "1--full and 2--old both carry a Done line"
      assert_equal 1, record[:qualified][:running_holder], "only 1--full ever writes a running line"
      assert_equal 1, record[:qualified][:model], "only 1--full ever carries model="
      assert_equal 0, record[:qualified][:hop], "no fixture here ever carries hop="
    end
  end

  # --- 5.4: expected model resolved through RunnerPolicy.model_for -------------

  def test_expected_model_resolved_through_runner_policy
    with_store_dir do |store|
      write_intent(store, "1--demo", transitions: node_transitions("n1", "sonnet"), node_kinds: { "n1" => "work" })

      record = GraphMeasureModels.read(store)
      row = record[:node_rows].find { |r| r[:node] == "n1" }
      refute_nil row
      assert_equal RunnerPolicy.model_for("work", config: {}), row[:expected]
      assert_equal "sonnet", row[:recorded]
      assert_empty record[:drift][:executor]
    end
  end

  # --- 5.5: verify resolves against the advisor default, not TIER_DEFAULTS -----

  def test_verify_resolves_the_advisor_default_not_tier_defaults
    refute AgentModels::TIER_DEFAULTS.key?("plastic-advisor"),
      "fixture assumption: plastic-advisor carries no TIER_DEFAULTS entry"

    with_store_dir do |store|
      write_intent(store, "1--demo", transitions: node_transitions("v1", "opus"), node_kinds: { "v1" => "verify" })

      record = GraphMeasureModels.read(store)
      row = record[:node_rows].find { |r| r[:node] == "v1" }
      assert_equal RunnerPolicy::DEFAULT_ADVISOR_MODEL, row[:expected]
      assert_equal "opus", row[:expected]
      assert_empty record[:drift][:advisor]
    end
  end

  # --- 5.6: the config chain - project, then global, then the shipped default --

  def test_config_chain_project_then_global_then_default
    with_store_dir do |store|
      write_intent(store, "1--demo", transitions: node_transitions("n1", "haiku"), node_kinds: { "n1" => "work" })

      shipped = GraphMeasureModels.read(store)
      row = shipped[:node_rows].find { |r| r[:node] == "n1" }
      assert_equal "sonnet", row[:expected]
      refute_empty shipped[:drift][:executor]

      global_cfg = { "agents" => { "models" => { "plastic-executor" => "haiku" } } }
      with_global = GraphMeasureModels.read(store, global_config: global_cfg)
      row_g = with_global[:node_rows].find { |r| r[:node] == "n1" }
      assert_equal "haiku", row_g[:expected]
      assert_empty with_global[:drift][:executor]

      project_cfg = { "agents" => { "models" => { "plastic-executor" => "opus" } } }
      with_project = GraphMeasureModels.read(store, project_config: project_cfg, global_config: global_cfg)
      row_p = with_project[:node_rows].find { |r| r[:node] == "n1" }
      assert_equal "opus", row_p[:expected], "project override must win over the global override"
    end
  end

  # --- 5.7: every recorded model= that differs is listed, per role -------------

  def test_recorded_model_differing_from_config_is_listed
    with_store_dir do |store|
      write_intent(store, "500--drift-demo", transitions: node_transitions("n1", "opus"), node_kinds: { "n1" => "work" })

      record = GraphMeasureModels.read(store)
      drift = record[:drift][:executor]
      assert_equal 1, drift.length
      entry = drift.first
      assert_equal "500--drift-demo", entry[:intent]
      assert_equal "n1", entry[:node]
      assert_equal "opus", entry[:recorded]
      assert_equal "sonnet", entry[:expected]
    end
  end

  # --- 5.8: the current store, real fixtures, produces no drift ----------------

  def test_current_store_produces_no_drift
    with_store_dir do |store|
      FileUtils.cp_r(DIR_340, File.join(store, File.basename(DIR_340)))
      FileUtils.cp_r(DIR_337, File.join(store, File.basename(DIR_337)))

      record = GraphMeasureModels.read(store)
      assert_empty record[:drift][:executor]
      assert_empty record[:drift][:advisor]
      assert_includes record[:excluded_no_model], File.basename(DIR_337)
    end
  end

  # --- 5.9: a kind never recorded is unmeasured, never drift --------------------

  def test_never_recorded_kind_is_unmeasured_not_drift
    with_store_dir do |store|
      write_intent(store, "1--demo", transitions: node_transitions("n1", "sonnet"), node_kinds: { "n1" => "work" })

      record = GraphMeasureModels.read(store)
      assert_includes record[:unmeasured_kinds], "research"
      assert_includes record[:unmeasured_kinds], "verify"
      refute_includes record[:unmeasured_kinds], "work"
      assert_empty record[:drift][:executor]
      assert_empty record[:drift][:advisor]
    end
  end

  # --- 5.10: a ledger with no model= anywhere is excluded and named -------------

  def test_ledger_without_model_excluded_and_named
    with_store_dir do |store|
      FileUtils.cp_r(DIR_337, File.join(store, File.basename(DIR_337)))

      record = GraphMeasureModels.read(store)
      assert_equal [File.basename(DIR_337)], record[:excluded_no_model]
      assert_empty record[:node_rows]
    end
  end

  # --- 5.11: the kind source is flagged in the comparison -----------------------

  def test_kind_source_flagged_in_the_model_comparison
    with_store_dir do |store|
      dir = write_intent(store, "1--demo",
                          transitions: node_transitions("n1", "sonnet") + node_transitions("n2", "sonnet"),
                          node_kinds: { "n1" => "work" })
      refute File.exist?(File.join(dir, "nodes", "n2.md"))

      record = GraphMeasureModels.read(store)
      row1 = record[:node_rows].find { |r| r[:node] == "n1" }
      row2 = record[:node_rows].find { |r| r[:node] == "n2" }
      assert_equal :node_file, row1[:kind_source]
      assert_equal :fallback, row2[:kind_source]
      assert_equal "work", row2[:kind]
    end
  end

  # --- 5.12: a store with no graph-era ledger is empty, never an error ----------

  def test_store_without_graph_era_ledgers_is_empty_not_an_error
    with_store_dir do |store|
      write_intent(store, "1--pre-graph", extra_lines: [
                     stage("2026-01-01T09:00:00Z", "Why", "spec.md created"),
                     stage("2026-01-01T09:30:00Z", "Done", "delivered"),
                   ])

      record = GraphMeasureModels.read(store)
      assert record[:ok]
      assert_empty record[:node_rows]
      assert_empty record[:drift][:executor]
      assert_empty record[:drift][:advisor]
    end
  end

  # --- 5.13: an unreadable intent directory is skipped and named, never aborts --

  def test_unreadable_intent_directory_is_skipped_and_named
    with_store_dir do |store|
      write_intent(store, "1--ok", transitions: node_transitions("n1", "sonnet"), node_kinds: { "n1" => "work" })
      blocked = write_intent(store, "2--blocked", transitions: node_transitions("n1", "sonnet"), node_kinds: { "n1" => "work" })
      File.chmod(0o000, blocked)

      begin
        record = GraphMeasureModels.read(store)
        assert_equal 2, record[:population][:total]
        assert_equal 1, record[:population][:unreadable].length
        assert_equal "2--blocked", record[:population][:unreadable].first[:id]
        assert_equal 1, record[:node_rows].count { |r| r[:intent] == "1--ok" }
        assert_equal 0, record[:node_rows].count { |r| r[:intent] == "2--blocked" }
      ensure
        File.chmod(0o755, blocked)
      end
    end
  end
end
