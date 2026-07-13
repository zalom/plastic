# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "json"
require "open3"

require_relative "../scripts/lib/opus_manual"

# Pure-logic coverage for OpusManual (intent 185). Single process, dependency
# injection only: no real /tmp, no real config, no real plugin install.
class OpusManualTest < Minitest::Test
  def setup
    @dir = Dir.mktmpdir("opus-manual-test")
    @plugin_root = File.join(@dir, "plugin")
    FileUtils.mkdir_p(File.join(@plugin_root, "manuals"))
    File.write(File.join(@plugin_root, "manuals", "operating-manual.md"), "# The Operating Manual\n\nBody.\n")
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

  # --- opus? ---

  def test_opus_matches_case_insensitively_and_as_a_substring
    assert OpusManual.opus?("claude-opus-4-8")
    assert OpusManual.opus?("Opus")
    assert OpusManual.opus?("OPUS")
    refute OpusManual.opus?("claude-sonnet-4-5")
    refute OpusManual.opus?("fable")
    refute OpusManual.opus?(nil)
  end

  # --- enabled? ---

  def test_enabled_true_for_nil_missing_or_any_non_false_value
    assert OpusManual.enabled?(-> { nil })
    assert OpusManual.enabled?(-> { "" })
    assert OpusManual.enabled?(-> { "true" })
    assert OpusManual.enabled?(-> { true })
  end

  def test_enabled_false_only_for_an_explicit_false
    refute OpusManual.enabled?(-> { false })
    refute OpusManual.enabled?(-> { "false" })
    refute OpusManual.enabled?(-> { "FALSE" })
    refute OpusManual.enabled?(-> { "  false  " })
  end

  def test_enabled_true_when_config_reader_raises
    assert OpusManual.enabled?(-> { raise "boom" })
  end

  # --- manual_text ---

  def test_manual_text_reads_the_shipped_file
    assert_includes OpusManual.manual_text(@plugin_root), "The Operating Manual"
  end

  def test_manual_text_nil_when_missing_or_unset
    assert_nil OpusManual.manual_text(File.join(@dir, "no-such-plugin-root"))
    assert_nil OpusManual.manual_text(nil)
    assert_nil OpusManual.manual_text("")
  end

  # --- pointer_text ---

  def test_pointer_text_names_all_three_advisor_agents
    %w[fable-advisor-s fable-advisor-m fable-advisor-l].each do |name|
      assert_includes OpusManual.pointer_text, name
    end
  end

  # --- injection: full decision matrix ---
  # model x enabled x marker-present x manual-present. Only the single cell
  # model=opus, enabled=true, marker=absent, manual=present may return text;
  # every other combination (12 axes x up to 2 values = 16 cells) must be nil.

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
          [true, false].each do |manual_present|
            Dir.mktmpdir do |cell_dir|
              state_dir = File.join(cell_dir, "state")
              FileUtils.mkdir_p(state_dir)
              session_id = "cell-session"
              File.write(File.join(state_dir, "#{OpusManual::MARKER_PREFIX}#{session_id}"), "") if marker_present

              plugin_root = File.join(cell_dir, "plugin")
              if manual_present
                FileUtils.mkdir_p(File.join(plugin_root, "manuals"))
                File.write(File.join(plugin_root, "manuals", "operating-manual.md"), "# The Operating Manual\n")
              end

              reader = enabled ? enabled_reader : disabled_reader

              text = OpusManual.injection(
                model: model_value, session_id: session_id, plugin_root: plugin_root,
                state_dir: state_dir, config_reader: reader
              )

              should_inject = model_key == :opus && enabled && !marker_present && manual_present
              context = "model=#{model_value.inspect} enabled=#{enabled} marker=#{marker_present} manual=#{manual_present}"
              if should_inject
                refute_nil text, "expected injection for #{context}"
                assert_includes text, "The Operating Manual"
                assert_includes text, "Fable advisor available"
              else
                assert_nil text, "expected no injection for #{context}"
              end
            end
          end
        end
      end
    end
  end

  # --- marker once-only behavior ---

  def test_marker_written_once_second_call_returns_nil
    session_id = "once-session"
    first = OpusManual.injection(
      model: "claude-opus-4-8", session_id: session_id, plugin_root: @plugin_root,
      state_dir: @state_dir, config_reader: enabled_reader
    )
    refute_nil first
    assert File.exist?(File.join(@state_dir, "#{OpusManual::MARKER_PREFIX}#{session_id}"))

    second = OpusManual.injection(
      model: "claude-opus-4-8", session_id: session_id, plugin_root: @plugin_root,
      state_dir: @state_dir, config_reader: enabled_reader
    )
    assert_nil second
  end

  # --- fail-open on an internal raise (distinct from a raising config_reader,
  # which enabled? already treats as enabled) ---

  def test_injection_returns_nil_on_internal_raise
    blocked_state_dir = File.join(@dir, "blocked-state")
    File.write(blocked_state_dir, "a file, not a directory")

    text = OpusManual.injection(
      model: "claude-opus-4-8", session_id: "s1", plugin_root: @plugin_root,
      state_dir: blocked_state_dir, config_reader: enabled_reader
    )
    assert_nil text
  end
end

# Subprocess smoke coverage for the two hook scripts (intent 185). No existing
# hook test exercises the opus-manual injection, so each script gets one
# IO.popen run per case, with a tmpdir plugin_root/state fixture and fake
# stdin JSON. PLASTIC_TMP isolates bridge derivation (hermeticity guard);
# PLASTIC_HOME isolates the shelled-out read-config call the injection's
# config_reader makes, so neither touches the real ~/.plastic.
class OpusManualSessionStartHookTest < Minitest::Test
  HOOK = File.expand_path("../scripts/hook-session-start", __dir__)

  def setup
    @dir = Dir.mktmpdir("opus-manual-session-start")
    @index = File.join(@dir, "INDEX.md")
    File.write(@index, "# Index\n\n## Active\n\n## Future\n")

    @plugin_root = File.join(@dir, "plugin")
    FileUtils.mkdir_p(File.join(@plugin_root, "manuals"))
    File.write(File.join(@plugin_root, "manuals", "operating-manual.md"), "# The Operating Manual\n\nBody text.\n")
    FileUtils.mkdir_p(File.join(@plugin_root, "scripts", "lib"))
    FileUtils.cp(File.expand_path("../scripts/read-config", __dir__), File.join(@plugin_root, "scripts", "read-config"))
    FileUtils.cp(File.expand_path("../scripts/lib/agent_models.rb", __dir__), File.join(@plugin_root, "scripts", "lib", "agent_models.rb"))

    @markers_before = Dir["/tmp/plastic-opus-manual-*"]
  end

  def teardown
    (Dir["/tmp/plastic-opus-manual-*"] - @markers_before).each { |f| FileUtils.rm_f(f) }
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
    assert_includes ctx, "Fable advisor available"
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
end

class OpusManualFallbackHookTest < Minitest::Test
  HOOK = File.expand_path("../hooks/opus-manual", __dir__)

  def setup
    @dir = Dir.mktmpdir("opus-manual-fallback")
    @plugin_root = File.join(@dir, "plugin")
    FileUtils.mkdir_p(File.join(@plugin_root, "manuals"))
    File.write(File.join(@plugin_root, "manuals", "operating-manual.md"), "# The Operating Manual\n\nBody text.\n")
    FileUtils.mkdir_p(File.join(@plugin_root, "scripts", "lib"))
    FileUtils.cp(File.expand_path("../scripts/read-config", __dir__), File.join(@plugin_root, "scripts", "read-config"))
    FileUtils.cp(File.expand_path("../scripts/lib/agent_models.rb", __dir__), File.join(@plugin_root, "scripts", "lib", "agent_models.rb"))

    @session_id = "opus-fallback-smoke-#{Process.pid}"
    @cache_path = "/tmp/plastic-model-#{@session_id}"
    @marker_path = "/tmp/plastic-opus-manual-#{@session_id}"
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
end
