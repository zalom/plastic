require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "json"
require_relative "../scripts/lib/savepoint"
require_relative "../scripts/lib/report_screen"

# Intent 317a, Batch 2 (S7/S9): the close-time record. S9 is the self-render
# gate - end-intent renders the delivered screen's sources on the intent's own
# record and refuses a hollow DELIVERED close with exit 7, before any terminal
# mutation (A9: INDEX, savepoint, and store untouched on refusal). This is
# intent 308's one deliberate exception to report-and-proceed. S7 stamps the
# live lock's run_mode into outcome.md frontmatter so mode survives the close.
class EndIntentCloseGateTest < Minitest::Test
  SCRIPT = File.expand_path("../scripts/end-intent", __dir__)
  SESSION = "gate-test-session".freeze

  def setup
    @root = Dir.mktmpdir("close-gate")
    @store = File.join(@root, "store")
    @tmp_bridge = File.join(@root, "tmp")
    FileUtils.mkdir_p(@store)
    FileUtils.mkdir_p(@tmp_bridge)
    @index = File.join(@root, "INDEX.md")
  end

  def teardown
    FileUtils.rm_rf(@root)
  end

  def run_end_intent(*args)
    env = { "CLAUDE_CODE_SESSION_ID" => nil, "PLASTIC_TMP" => @tmp_bridge }
    out = IO.popen(env, [RbConfig.ruby, SCRIPT, "--store", @store, "--id", "77",
                         "--disposition", "delivered", "--index", @index, "--no-commit",
                         "--session", SESSION, *args], err: [:child, :out], &:read)
    [out.strip, $?.exitstatus]
  end

  def build_intent(outcome:, action: nil)
    dir = File.join(@store, "77--gate")
    FileUtils.mkdir_p(File.join(dir, "actions"))
    File.write(File.join(dir, "77--gate.md"), <<~MD)
      ---
      id: "77"
      intent: "Gate demo"
      sources: []
      chain: []
      created: 2026-08-31
      author: human
      tags: []
      ---

      ## Intent
      Gate demo

      ## Context
      ctx

      ## Outcome
      (the result)

      ## Insights

      ## Links
      <!-- none -->
    MD
    File.write(File.join(dir, "spec.md"), "# Spec\n\n## Decisions\n- one\n")
    File.write(File.join(dir, "plan.md"), "# Plan\n\n## Steps\n1. step\n")
    File.write(File.join(dir, "checklist.md"), "# Checklist\n\n- [x] S1 the thing\n")
    File.write(File.join(dir, "savepoint.md"),
               "2026-08-31T09:00:00Z  What  77--gate.md\n2026-08-31T10:00:00Z  Exec  started\n")
    File.write(File.join(dir, "outcome.md"), outcome)
    File.write(File.join(dir, "actions", "ACTION_1.md"), action) if action
    File.write(File.join(dir, "delivery.lock"),
               JSON.generate("owner_session" => SESSION, "run_mode" => "auto",
                             "agent" => "plastic-enforcer"))
    File.write(@index, "# INDEX\n\n## Active\n- [77 - Gate demo](store/77--gate/77--gate.md) - demo\n\n## Completed\n")
    dir
  end

  LABELED_ACTION = <<~MD.freeze
    # ACTION_1

    ### S1 - the thing
    | Row | Failure mode | Test |
    | --- | --- | --- |
    | S1a | it breaks | a test |
  MD

  HOLLOW_OUTCOME = <<~MD.freeze
    ---
    disposition: delivered
    ---
    # Outcome: Gate demo

    ## Summary
    shipped

    ## Delivered
    - first thing that shipped
    - second thing that shipped

    ## Verification
    - suite green

    ## Needs you
    None

    ## Follow-ups
    None
  MD

  LABELED_OUTCOME = <<~MD.freeze
    ---
    disposition: delivered
    ---
    # Outcome: Gate demo

    ## Summary
    shipped

    ## Delivered
    | Row | What |
    | --- | --- |
    | S1 | the thing, delivered |

    ## Verification
    - suite green

    ## Needs you
    None

    ## Follow-ups
    None
  MD

  # --- S9a/S9b: hollow delivered close refuses with exit 7, nothing mutated ---

  def test_hollow_delivered_close_exits_7_with_nothing_mutated
    dir = build_intent(outcome: HOLLOW_OUTCOME, action: LABELED_ACTION)
    index_before = File.read(@index)
    savepoint_before = File.read(File.join(dir, "savepoint.md"))

    out, status = run_end_intent
    assert_equal 7, status, out
    assert_match(/hollow/, out)
    assert_match(/match no action-file heading/, out)
    assert_equal index_before, File.read(@index)
    assert_equal savepoint_before, File.read(File.join(dir, "savepoint.md"))
    refute_match(/mode:/, File.read(File.join(dir, "outcome.md")))
  end

  # --- S9e: the deliberate override closes with a warn ---

  def test_allow_hollow_report_overrides_with_a_warn
    build_intent(outcome: HOLLOW_OUTCOME, action: LABELED_ACTION)
    out, status = run_end_intent("--allow-hollow-report")
    assert_equal 0, status, out
    assert_match(/hollow/, out)
  end

  # --- S9 happy path + S7a/S7b: labeled close passes and mode is stamped ---

  def test_labeled_close_passes_the_gate_and_stamps_mode
    dir = build_intent(outcome: LABELED_OUTCOME, action: LABELED_ACTION)
    out, status = run_end_intent
    assert_equal 0, status, out
    fm = File.read(File.join(dir, "outcome.md")).split("---", 3)[1]
    assert_includes fm, "mode: auto"
    assert_equal "auto", ReportScreen.mode(dir)
  end

  # --- S9c/S9d live in end_intent_test.rb: abandoned and backfill-only closes
  # keep exiting 0; those existing tests are this gate's exemption proof. ---

  # --- intent 330, O1.8/O1.9: the fence fix moves the gate in both
  # directions (D13) ------------------------------------------------------

  FENCED_LABEL_ACTION = <<~MD.freeze
    # ACTION_1

    ```text
    ### S1 - shown only as a fenced example, never a real heading
    ```

    ### T1 - the real heading, no S-label at all
    | Row | Op |
    | --- | --- |
    | 1 | a |
  MD

  # O1.8: an S-label heading that lives ONLY inside a fenced example must
  # never arm the hollow gate - the record never claims the labeled
  # convention (no REAL S-labeled heading exists), so a hollow-shaped
  # outcome still closes clean rather than being refused on a phantom label.
  def test_hollow_gate_ignores_an_s_label_heading_inside_a_fence
    build_intent(outcome: HOLLOW_OUTCOME, action: FENCED_LABEL_ACTION)
    out, status = run_end_intent
    assert_equal 0, status, out
  end

  MATRIX_AFTER_FENCE_ACTION = <<~MD.freeze
    # ACTION_1

    ### S1 - the real heading

    a worked example:

    ```ruby
    # a comment that looks like a heading
    def x; end
    ```

    | Row | Failure mode | Test |
    | --- | --- | --- |
    | 1 | it breaks | a test |
  MD

  MATRIX_AFTER_FENCE_OUTCOME = <<~MD.freeze
    ---
    disposition: delivered
    ---
    # Outcome: Gate demo

    ## Summary
    shipped

    ## Delivered
    | Row | What |
    | --- | --- |
    | S1 | the thing, delivered |

    ## Verification
    - suite green

    ## Needs you
    None

    ## Follow-ups
    None
  MD

  # O1.9: before the fence fix, a "#" comment inside the worked example cut
  # S1's section short, losing the matrix that follows the fence, and
  # proven_by(S1) rendered "not recorded" - refusing a record that is
  # genuinely proven. The fence-aware reader must see the matrix and close
  # clean.
  def test_hollow_gate_counts_a_matrix_after_a_closed_fence
    build_intent(outcome: MATRIX_AFTER_FENCE_OUTCOME, action: MATRIX_AFTER_FENCE_ACTION)
    out, status = run_end_intent
    assert_equal 0, status, out
  end
end
