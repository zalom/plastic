# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "json"
require "open3"

require_relative "../scripts/lib/model_instructions"

# Pure-logic coverage for ModelInstructions (intent 185). Single process, dependency
# injection only: no real /tmp, no real config, no real plugin install.
class ModelInstructionsTest < Minitest::Test
  def setup
    @dir = Dir.mktmpdir("model-instructions-test")
    @plugin_root = File.join(@dir, "plugin")
    FileUtils.mkdir_p(File.join(@plugin_root, "model_instructions"))
    File.write(File.join(@plugin_root, "model_instructions", "operating-manual.md"), "# The Operating Manual\n\nBody.\n")
    @state_dir = File.join(@dir, "state")
    FileUtils.mkdir_p(@state_dir)
  end

  def teardown
    FileUtils.rm_rf(@dir)
  end

  def enabled_reader
    -> { nil }
  end

  def disabled_reader
    -> { "false" }
  end

  # --- file_for ---

  def test_file_for_matches_opus_case_insensitively_and_as_a_substring
    assert_equal "operating-manual.md", ModelInstructions.file_for("claude-opus-4-8")
    assert_equal "operating-manual.md", ModelInstructions.file_for("Opus")
    assert_equal "operating-manual.md", ModelInstructions.file_for("OPUS")
    assert_nil ModelInstructions.file_for("claude-sonnet-4-5")
    assert_nil ModelInstructions.file_for("fable")
    assert_nil ModelInstructions.file_for(nil)
  end

  # --- enabled? ---

  def test_enabled_true_for_nil_missing_or_any_non_false_value
    assert ModelInstructions.enabled?(-> { nil })
    assert ModelInstructions.enabled?(-> { "" })
    assert ModelInstructions.enabled?(-> { "true" })
    assert ModelInstructions.enabled?(-> { true })
  end

  def test_enabled_false_only_for_an_explicit_false
    refute ModelInstructions.enabled?(-> { false })
    refute ModelInstructions.enabled?(-> { "false" })
    refute ModelInstructions.enabled?(-> { "FALSE" })
    refute ModelInstructions.enabled?(-> { "  false  " })
  end

  def test_enabled_true_when_config_reader_raises
    assert ModelInstructions.enabled?(-> { raise "boom" })
  end

  # --- instruction_text ---

  def test_instruction_text_reads_the_shipped_file
    assert_includes ModelInstructions.instruction_text("operating-manual.md", @plugin_root), "The Operating Manual"
  end

  def test_instruction_text_nil_when_missing_or_unset
    # fallback_dir is pinned to a guaranteed-empty tmp path (never the real
    # ~/.plastic/model_instructions default) so this stays hermetic regardless of
    # what is actually installed on the machine running the suite.
    empty_fallback = File.join(@dir, "no-such-fallback")
    assert_nil ModelInstructions.instruction_text("operating-manual.md", File.join(@dir, "no-such-plugin-root"), fallback_dir: empty_fallback)
    assert_nil ModelInstructions.instruction_text("operating-manual.md", nil, fallback_dir: empty_fallback)
    assert_nil ModelInstructions.instruction_text("operating-manual.md", "", fallback_dir: empty_fallback)
  end

  # --- instruction_text fallback resolution (intent 185): plugin_root first,
  # then a DI'd fallback_dir (default ~/.plastic/model_instructions in
  # production, where the installer syncs both documents on every install and
  # update) ---

  def test_instruction_text_prefers_plugin_root_when_both_resolve
    fallback = File.join(@dir, "fallback")
    FileUtils.mkdir_p(fallback)
    File.write(File.join(fallback, "operating-manual.md"), "# Fallback copy\n")

    text = ModelInstructions.instruction_text("operating-manual.md", @plugin_root, fallback_dir: fallback)
    assert_includes text, "The Operating Manual"
    refute_includes text, "Fallback copy"
  end

  def test_instruction_text_uses_fallback_when_plugin_root_empty
    fallback = File.join(@dir, "fallback")
    FileUtils.mkdir_p(fallback)
    File.write(File.join(fallback, "operating-manual.md"), "# Fallback copy\n")

    assert_includes ModelInstructions.instruction_text("operating-manual.md", "", fallback_dir: fallback), "Fallback copy"
    assert_includes ModelInstructions.instruction_text("operating-manual.md", nil, fallback_dir: fallback), "Fallback copy"
  end

  def test_instruction_text_uses_fallback_when_plugin_root_file_missing
    fallback = File.join(@dir, "fallback")
    FileUtils.mkdir_p(fallback)
    File.write(File.join(fallback, "operating-manual.md"), "# Fallback copy\n")

    unreadable_plugin_root = File.join(@dir, "no-such-plugin-root")
    assert_includes ModelInstructions.instruction_text("operating-manual.md", unreadable_plugin_root, fallback_dir: fallback), "Fallback copy"
  end

  def test_instruction_text_nil_when_plugin_root_and_fallback_both_missing
    assert_nil ModelInstructions.instruction_text("operating-manual.md", File.join(@dir, "no-such-plugin-root"),
                                                    fallback_dir: File.join(@dir, "no-such-fallback"))
  end

  # --- pointer_text ---

  def test_pointer_text_names_plastic_advisor
    assert_includes ModelInstructions.pointer_text, "plastic-advisor"
  end

  # --- injection: full decision matrix ---
  # model x model_instructions_enabled x marker-present x file-present. Only the
  # single cell model=opus, enabled=true, marker=absent, file=present may return
  # text; every other combination (4 axes, up to 2 values each) must be nil.
  # advisor_reader is fixed enabled here; its effect is on CONTENT, never on
  # nil/non-nil, covered separately below.

  MODELS = {
    opus: "claude-opus-4-8",
    sonnet: "claude-sonnet-4-5",
    fable: "fable",
    nil_model: nil
  }.freeze

  def test_injection_matrix_only_the_one_valid_cell_returns_text
    MODELS.each do |model_key, model_value|
      [true, false].each do |enabled|
        [true, false].each do |marker_present|
          [true, false].each do |file_present|
            Dir.mktmpdir do |cell_dir|
              state_dir = File.join(cell_dir, "state")
              FileUtils.mkdir_p(state_dir)
              session_id = "cell-session"
              File.write(File.join(state_dir, "#{ModelInstructions::MARKER_PREFIX}#{session_id}"), "") if marker_present

              plugin_root = File.join(cell_dir, "plugin")
              if file_present
                FileUtils.mkdir_p(File.join(plugin_root, "model_instructions"))
                File.write(File.join(plugin_root, "model_instructions", "operating-manual.md"), "# The Operating Manual\n")
              end

              reader = enabled ? enabled_reader : disabled_reader

              text = ModelInstructions.injection(
                model: model_value, session_id: session_id, plugin_root: plugin_root,
                state_dir: state_dir, model_instructions_reader: reader, advisor_reader: enabled_reader,
                # Pinned to a guaranteed-empty tmp path: the file_present axis must
                # be decided by plugin_root alone, never by a real
                # ~/.plastic/model_instructions the fallback default would
                # otherwise silently pick up.
                fallback_dir: File.join(cell_dir, "no-such-fallback")
              )

              should_inject = model_key == :opus && enabled && !marker_present && file_present
              context = "model=#{model_value.inspect} enabled=#{enabled} marker=#{marker_present} file=#{file_present}"
              if should_inject
                refute_nil text, "expected injection for #{context}"
                assert_includes text, "The Operating Manual"
                assert_includes text, "Advisor available"
              else
                assert_nil text, "expected no injection for #{context}"
              end
            end
          end
        end
      end
    end
  end

  # --- advisor_reader gates CONTENT only, never nil/non-nil (intent 185
  # ACTION-7): the instruction text still lands when the advisor is disabled or
  # not installed; only the pointer paragraph is withheld ---

  def test_advisor_disabled_still_injects_instructions_without_the_pointer
    text = ModelInstructions.injection(
      model: "claude-opus-4-8", session_id: "advisor-off-session", plugin_root: @plugin_root,
      state_dir: @state_dir, model_instructions_reader: enabled_reader, advisor_reader: disabled_reader
    )
    refute_nil text, "instructions must still inject when only the advisor pointer is disabled"
    assert_includes text, "The Operating Manual"
    refute_includes text, "Advisor available"
    refute_includes text, "plastic-advisor"
  end

  def test_advisor_enabled_appends_the_pointer
    text = ModelInstructions.injection(
      model: "claude-opus-4-8", session_id: "advisor-on-session", plugin_root: @plugin_root,
      state_dir: @state_dir, model_instructions_reader: enabled_reader, advisor_reader: enabled_reader
    )
    assert_includes text, "Advisor available"
    assert_includes text, "plastic-advisor"
  end

  # --- simulated manifest install (intent 185 Done-when): an empty
  # CLAUDE_PLUGIN_ROOT (a flat, non-plugin install) must still inject via the
  # fallback_dir the installer synced the documents to (~/.plastic/model_instructions
  # in production, DI'd here to a tmp dir standing in for it) ---

  def test_injection_via_fallback_dir_with_empty_plugin_root_simulates_flat_install
    fallback = File.join(@dir, "plastic-home-model-instructions")
    FileUtils.mkdir_p(fallback)
    File.write(File.join(fallback, "operating-manual.md"), "# The Operating Manual\n\nBody.\n")

    text = ModelInstructions.injection(
      model: "claude-opus-4-8", session_id: "flat-install-session", plugin_root: "",
      state_dir: File.join(@dir, "state2"), model_instructions_reader: enabled_reader, advisor_reader: enabled_reader,
      fallback_dir: fallback
    )
    refute_nil text, "a simulated manifest install with an empty CLAUDE_PLUGIN_ROOT must still inject via fallback_dir"
    assert_includes text, "The Operating Manual"
  end

  # --- marker once-only behavior ---

  def test_marker_written_once_second_call_returns_nil
    session_id = "once-session"
    first = ModelInstructions.injection(
      model: "claude-opus-4-8", session_id: session_id, plugin_root: @plugin_root,
      state_dir: @state_dir, model_instructions_reader: enabled_reader, advisor_reader: enabled_reader
    )
    refute_nil first
    assert File.exist?(File.join(@state_dir, "#{ModelInstructions::MARKER_PREFIX}#{session_id}"))

    second = ModelInstructions.injection(
      model: "claude-opus-4-8", session_id: session_id, plugin_root: @plugin_root,
      state_dir: @state_dir, model_instructions_reader: enabled_reader, advisor_reader: enabled_reader
    )
    assert_nil second
  end

  # --- fail-open on an internal raise (distinct from a raising config_reader,
  # which enabled? already treats as enabled) ---

  def test_injection_returns_nil_on_internal_raise
    blocked_state_dir = File.join(@dir, "blocked-state")
    File.write(blocked_state_dir, "a file, not a directory")

    text = ModelInstructions.injection(
      model: "claude-opus-4-8", session_id: "s1", plugin_root: @plugin_root,
      state_dir: blocked_state_dir, model_instructions_reader: enabled_reader, advisor_reader: enabled_reader
    )
    assert_nil text
  end
end

# Subprocess smoke coverage for the two hook scripts (intent 185). Each script
# gets one IO.popen run per case, with a tmpdir plugin_root/state fixture and
# fake stdin JSON. PLASTIC_TMP isolates bridge derivation (hermeticity guard);
# PLASTIC_HOME isolates the shelled-out read-config call the injection's
# readers make, so neither touches the real ~/.plastic.
class ModelInstructionsSessionStartHookTest < Minitest::Test
  HOOK = File.expand_path("../scripts/hook-session-start", __dir__)

  def setup
    @dir = Dir.mktmpdir("model-instructions-session-start")
    @index = File.join(@dir, "INDEX.md")
    File.write(@index, "# Index\n\n## Active\n\n## Future\n")

    @plugin_root = File.join(@dir, "plugin")
    FileUtils.mkdir_p(File.join(@plugin_root, "model_instructions"))
    File.write(File.join(@plugin_root, "model_instructions", "operating-manual.md"), "# The Operating Manual\n\nBody text.\n")
    FileUtils.mkdir_p(File.join(@plugin_root, "scripts", "lib"))
    FileUtils.cp(File.expand_path("../scripts/read-config", __dir__), File.join(@plugin_root, "scripts", "read-config"))
    FileUtils.cp(File.expand_path("../scripts/lib/agent_models.rb", __dir__), File.join(@plugin_root, "scripts", "lib", "agent_models.rb"))

    @markers_before = Dir["/tmp/plastic-model-instructions-*"]
  end

  def teardown
    (Dir["/tmp/plastic-model-instructions-*"] - @markers_before).each { |f| FileUtils.rm_f(f) }
    FileUtils.rm_rf(@dir)
  end

  def run_hook(stdin_json)
    out = nil
    IO.popen({ "PLASTIC_TMP" => @dir, "PLASTIC_HOME" => @dir, "CLAUDE_CODE_SESSION_ID" => nil },
             ["ruby", HOOK, @index, @dir, "global", @plugin_root], "r+") do |io|
      io.write(stdin_json)
      io.close_write
      out = io.read
    end
    [out, $?]
  end

  def context_from(out)
    JSON.parse(out).dig("hookSpecificOutput", "additionalContext").to_s
  rescue JSON::ParserError
    ""
  end

  def test_opus_model_in_stdin_injects_the_manual
    out, status = run_hook(JSON.generate({ "session_id" => "opus-smoke-1", "model" => "claude-opus-4-8" }))
    assert_equal 0, status.exitstatus
    ctx = context_from(out)
    assert_includes ctx, "The Operating Manual"
    assert_includes ctx, "Advisor available"
  end

  def test_sonnet_model_in_stdin_emits_no_manual
    out, status = run_hook(JSON.generate({ "session_id" => "opus-smoke-2", "model" => "claude-sonnet-4-5" }))
    assert_equal 0, status.exitstatus
    refute_includes context_from(out), "The Operating Manual"
  end

  def test_fable_model_in_stdin_emits_no_manual
    out, status = run_hook(JSON.generate({ "session_id" => "opus-smoke-3", "model" => "fable" }))
    assert_equal 0, status.exitstatus
    refute_includes context_from(out), "The Operating Manual"
  end

  def test_no_model_field_emits_no_manual
    out, status = run_hook(JSON.generate({ "session_id" => "opus-smoke-4" }))
    assert_equal 0, status.exitstatus
    refute_includes context_from(out), "The Operating Manual"
  end

  def test_garbage_stdin_exits_zero
    _out, status = run_hook("{not valid json")
    assert_equal 0, status.exitstatus
  end

  # Fallback resolution (intent 185): hook-session-start derives fallback_dir
  # from its own store-root ARGV (store_root/model_instructions). Give it a
  # plugin_root that resolves config but has no model_instructions/ of its own,
  # and pre-seed store_root/model_instructions with the manual, proving the
  # derived fallback actually gets passed through and used, hermetically (never
  # the real ~/.plastic).
  def test_plugin_root_without_model_instructions_falls_back_to_store_root
    plugin_root_no_docs = File.join(@dir, "plugin-no-docs")
    FileUtils.mkdir_p(File.join(plugin_root_no_docs, "scripts", "lib"))
    FileUtils.cp(File.expand_path("../scripts/read-config", __dir__),
                 File.join(plugin_root_no_docs, "scripts", "read-config"))
    FileUtils.cp(File.expand_path("../scripts/lib/agent_models.rb", __dir__),
                 File.join(plugin_root_no_docs, "scripts", "lib", "agent_models.rb"))

    FileUtils.mkdir_p(File.join(@dir, "model_instructions"))
    File.write(File.join(@dir, "model_instructions", "operating-manual.md"), "# The Operating Manual\n\nFallback body.\n")

    out = nil
    IO.popen({ "PLASTIC_TMP" => @dir, "PLASTIC_HOME" => @dir, "CLAUDE_CODE_SESSION_ID" => nil },
             ["ruby", HOOK, @index, @dir, "global", plugin_root_no_docs], "r+") do |io|
      io.write(JSON.generate({ "session_id" => "opus-smoke-fallback", "model" => "claude-opus-4-8" }))
      io.close_write
      out = io.read
    end
    status = $?

    assert_equal 0, status.exitstatus
    ctx = context_from(out)
    assert_includes ctx, "The Operating Manual"
    assert_includes ctx, "Fallback body."
  end
end

class ModelInstructionsFallbackHookTest < Minitest::Test
  HOOK = File.expand_path("../hooks/model-instructions", __dir__)

  def setup
    @dir = Dir.mktmpdir("model-instructions-fallback")
    @plugin_root = File.join(@dir, "plugin")
    FileUtils.mkdir_p(File.join(@plugin_root, "model_instructions"))
    File.write(File.join(@plugin_root, "model_instructions", "operating-manual.md"), "# The Operating Manual\n\nBody text.\n")
    FileUtils.mkdir_p(File.join(@plugin_root, "scripts", "lib"))
    FileUtils.cp(File.expand_path("../scripts/read-config", __dir__), File.join(@plugin_root, "scripts", "read-config"))
    FileUtils.cp(File.expand_path("../scripts/lib/agent_models.rb", __dir__), File.join(@plugin_root, "scripts", "lib", "agent_models.rb"))

    @session_id = "model-instructions-fallback-smoke-#{Process.pid}"
    @cache_path = "/tmp/plastic-model-#{@session_id}"
    @marker_path = "/tmp/plastic-model-instructions-#{@session_id}"
  end

  def teardown
    FileUtils.rm_f(@cache_path)
    FileUtils.rm_f(@marker_path)
    FileUtils.rm_rf(@dir)
  end

  def run_hook(stdin_json)
    out = nil
    IO.popen({ "CLAUDE_PLUGIN_ROOT" => @plugin_root }, [HOOK], "r+") do |io|
      io.write(stdin_json)
      io.close_write
      out = io.read
    end
    [out, $?]
  end

  def test_cached_opus_model_injects_the_manual_exactly_once
    File.write(@cache_path, "Opus")

    out1, status1 = run_hook(JSON.generate({ "session_id" => @session_id }))
    assert_equal 0, status1.exitstatus
    assert_includes out1, "The Operating Manual"

    out2, status2 = run_hook(JSON.generate({ "session_id" => @session_id }))
    assert_equal 0, status2.exitstatus
    assert_equal "", out2, "second call must print nothing (marker already set)"
  end

  def test_no_cache_file_prints_nothing_and_exits_zero
    out, status = run_hook(JSON.generate({ "session_id" => @session_id }))
    assert_equal 0, status.exitstatus
    assert_equal "", out
  end

  def test_cached_non_opus_model_prints_nothing
    File.write(@cache_path, "Sonnet")
    out, status = run_hook(JSON.generate({ "session_id" => @session_id }))
    assert_equal 0, status.exitstatus
    assert_equal "", out
  end

  def test_garbage_stdin_prints_nothing_and_exits_zero
    File.write(@cache_path, "Opus")
    out, status = run_hook("{not valid json")
    assert_equal 0, status.exitstatus
    assert_equal "", out
  end

  # Simulated manifest install (intent 185 Done-when): hook-model-instructions
  # passes no explicit fallback_dir, so this exercises ModelInstructions' real
  # default (~/.plastic/model_instructions) end to end. HOME is redirected to a
  # tmp dir so the real home directory is never touched; CLAUDE_PLUGIN_ROOT is
  # empty, standing in for a flat, non-plugin install.
  def test_empty_plugin_root_falls_back_to_home_plastic_model_instructions
    fake_home = File.join(@dir, "fake-home")
    FileUtils.mkdir_p(File.join(fake_home, ".plastic", "model_instructions"))
    File.write(File.join(fake_home, ".plastic", "model_instructions", "operating-manual.md"),
               "# The Operating Manual\n\nBody.\n")
    # hook-model-instructions resolves read-config under ~/.plastic/scripts when
    # plugin_root is empty; seed it so the config_reader shell-out is clean
    # (no stray "No such file" stderr) rather than merely harmless.
    FileUtils.mkdir_p(File.join(fake_home, ".plastic", "scripts", "lib"))
    FileUtils.cp(File.expand_path("../scripts/read-config", __dir__),
                 File.join(fake_home, ".plastic", "scripts", "read-config"))
    FileUtils.cp(File.expand_path("../scripts/lib/agent_models.rb", __dir__),
                 File.join(fake_home, ".plastic", "scripts", "lib", "agent_models.rb"))

    sid = "model-instructions-fallback-home-#{Process.pid}"
    cache_path = "/tmp/plastic-model-#{sid}"
    marker_path = "/tmp/plastic-model-instructions-#{sid}"
    File.write(cache_path, "Opus")

    out = nil
    IO.popen({ "CLAUDE_PLUGIN_ROOT" => "", "HOME" => fake_home }, [HOOK], "r+") do |io|
      io.write(JSON.generate({ "session_id" => sid }))
      io.close_write
      out = io.read
    end
    status = $?

    assert_equal 0, status.exitstatus
    assert_includes out, "The Operating Manual"
  ensure
    FileUtils.rm_f(cache_path)
    FileUtils.rm_f(marker_path)
  end
end
