# encoding: UTF-8
# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "time"
require "open3"
require "json"

require_relative "../scripts/doctor"
require_relative "../scripts/lib/graph_measure_models"
require_relative "../scripts/lib/node_ledger"

# DoctorRequalificationTest (intent 343, G10, n7): D42's doctor rule - when a
# recorded model= no longer matches what RunnerPolicy.model_for resolves for
# that node's kind today, the store's measurements were taken under a
# different system and need re-qualifying before anyone acts on them. Warns,
# never fails (D10). Reads GraphMeasureModels' own comparison (D16) rather
# than reimplementing it. Lives in scripts/doctor.rb, next to
# node_graph_checks, never doctor_core.rb (D11; proven by
# test/doctor_core_split_test.rb's exact-set boot-path assertion).
#
# Hermetic throughout: every fixture lives in a Dir.mktmpdir, and no test
# reads the real ~/.plastic.
class DoctorRequalificationTest < Minitest::Test
  RUNNING = { holder: "auto-1", expires: "2099-01-01T00:00:00Z", packet: "abc123" }.freeze

  def setup
    @home = Dir.mktmpdir("plastic-doctor-requalification")
    @store = File.join(@home, "store")
    FileUtils.mkdir_p(@store)
    write_index
  end

  def teardown
    FileUtils.remove_entry(@home) if @home && Dir.exist?(@home)
  end

  def write_index
    File.write(File.join(@home, "INDEX.md"), "# Index\n\n## Active\n\n## Future\n\n## Clusters\n\n" \
                                              "## Abandoned\n\n## Completed\n\n## Relocated\n(none)\n")
  end

  def stamp(str)
    Time.iso8601(str)
  end

  def transition(ts, subject, state, fields: {})
    NodeLedger.transition_line(subject: subject, state: state, fields: fields, now: stamp(ts))
  end

  # One running line then one terminal line for `id`, both carrying `model=`
  # (mirrors GraphMeasureModelsTest's own fixture shape - `running` requires
  # model=, `done` merely accepts it).
  def node_transitions(id, model, terminal: "done")
    [
      transition("2026-01-01T09:00:00Z", id, "running", fields: RUNNING.merge(model: model)),
      transition("2026-01-01T09:10:00Z", id, terminal,
                  fields: RUNNING.merge(model: model, gates: "suite", commit: "abc1234")),
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

  def write_intent(id, transitions: [], node_kinds: {}, extra_lines: [])
    dir = File.join(@store, id)
    FileUtils.mkdir_p(dir)
    File.write(File.join(dir, "#{id}.md"), "---\nid: \"#{id.split('--').first}\"\nintent: t\n---\n\n## Intent\nb\n")
    content = (Array(transitions).flatten + Array(extra_lines)).join
    File.write(File.join(dir, "savepoint.md"), content) unless content.empty?
    node_kinds.each { |nid, kind| write_node_file(dir, nid, kind) }
    dir
  end

  def doctor = Doctor.new(plastic_home: @home)

  def check(name)
    doctor.check_conventions.find { |c| c[:name] == name }
  end

  # --- 7.1: the rule appears in the doctor's check list -------------------

  def test_check_appears_in_doctor_output
    write_intent("1--demo", transitions: node_transitions("n1", "sonnet"), node_kinds: { "n1" => "work" })
    refute_nil check("model_requalification"),
               "the re-qualification rule must appear among check_conventions' checks"
  end

  # --- 7.2: warn, never fail, on a real drift ------------------------------

  def test_model_drift_warns_and_does_not_fail
    write_intent("1--demo", transitions: node_transitions("v1", "sonnet"), node_kinds: { "v1" => "verify" })

    result = check("model_requalification")
    assert_equal "warn", result[:status],
                 "a model change is routine; it must never turn the doctor red"
  end

  # --- 7.3: pass quietly on the store as it stands -------------------------

  def test_current_store_passes_quietly
    write_intent("1--demo",
                 transitions: node_transitions("n1", "sonnet") + node_transitions("v1", "opus"),
                 node_kinds: { "n1" => "work", "v1" => "verify" })

    result = check("model_requalification")
    assert_equal "pass", result[:status],
                 "work=sonnet and verify=opus both match RunnerPolicy's shipped defaults today"
    assert_empty result[:details]
  end

  # --- 7.4: the finding names the role, both models, and the affected node ---

  def test_finding_names_role_models_and_affected_intents
    write_intent("1--demo", transitions: node_transitions("v1", "sonnet"), node_kinds: { "v1" => "verify" })

    result = check("model_requalification")
    detail = result[:details].join(" ")
    assert_includes detail, "1--demo", "the finding must name the affected intent"
    assert_includes detail, "v1", "the finding must name the affected node"
    assert_includes detail, "advisor", "the finding must name the role"
    assert_includes detail, "sonnet", "the finding must name the recorded model"
    assert_includes detail, "opus", "the finding must name the current model"
  end

  # --- 7.5: pass cleanly when no store holds a graph-era ledger ------------

  def test_no_graph_era_ledger_passes_cleanly
    write_intent("1--demo", extra_lines: ["2026-01-01T09:00:00Z  Exec  started\n"])

    result = check("model_requalification")
    assert_equal "pass", result[:status]
    assert_empty result[:details]
  end

  # --- 7.6: an unreadable store is skipped, never fatal --------------------

  def test_unreadable_store_is_skipped_not_fatal
    write_intent("1--demo", transitions: node_transitions("v1", "sonnet"), node_kinds: { "v1" => "verify" })

    bad_store = File.join(@home, "projects", "proj1", "store")
    FileUtils.mkdir_p(bad_store)
    File.chmod(0o000, bad_store)

    checks = begin
      doctor.model_requalification_checks
    ensure
      File.chmod(0o755, bad_store)
    end

    result = checks.find { |c| c[:name] == "model_requalification" }
    refute_nil result, "one unreadable store must not take the whole rule down"
    assert_equal "warn", result[:status], "the readable store's own drift must still be reported"
    assert_includes result[:details].join(" "), "1--demo"
  end

  # --- 7.9: a real subprocess run of doctor.rb reports the finding ---------

  def test_subprocess_doctor_reports_the_finding
    write_intent("1--demo", transitions: node_transitions("v1", "sonnet"), node_kinds: { "v1" => "verify" })

    env = { "PLASTIC_HOME" => @home }
    script = File.expand_path("../../scripts/doctor.rb", __FILE__)
    stdout, _stderr, _status = Open3.capture3(env, "ruby", script)

    data = JSON.parse(stdout)
    found = data["checks"].find { |c| c["name"] == "model_requalification" }
    refute_nil found, "model_requalification must appear in a real doctor.rb subprocess run"
    assert_equal "warn", found["status"]
    assert(found["details"].any? { |d| d.include?("1--demo") && d.include?("v1") })
  end

  # --- 7.10: the rule reads GraphMeasureModels rather than reimplementing it -

  def test_rule_reads_the_models_module
    canned = {
      ok: true,
      population: { total: 1, with_savepoint: 1, without_savepoint: 0, unreadable: [] },
      qualified: { done: 1, running_holder: 1, model: 1, hop: 0 },
      excluded_no_model: [],
      node_rows: [],
      drift: {
        executor: [{ intent: "9--stub", node: "n9", kind: "work", kind_source: :node_file,
                      role: :executor, recorded: "stub-old", expected: "stub-new" }],
        advisor: [],
      },
      unmeasured_kinds: [],
    }

    original = GraphMeasureModels.method(:read)
    GraphMeasureModels.define_singleton_method(:read) { |*_args, **_kwargs| canned }

    result = begin
      write_intent("1--demo")
      check("model_requalification")
    ensure
      GraphMeasureModels.define_singleton_method(:read, original)
    end

    assert_equal "warn", result[:status]
    detail = result[:details].join(" ")
    assert_includes detail, "9--stub", "a value only the stubbed GraphMeasureModels.read could supply"
    assert_includes detail, "stub-old"
    assert_includes detail, "stub-new"
  end
end
