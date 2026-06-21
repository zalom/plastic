require "minitest/autorun"
require "tmpdir"
require "fileutils"
require_relative "../scripts/lib/qmd_hook"

class QmdHookTest < Minitest::Test
  HITS_JSON = <<~JSON
    [{"docid":"#a1","score":0.81,"file":"qmd://plastic-global/15--enforce/15.md","line":1,"title":"Enforce Plastic supremacy","snippet":"x"}]
  JSON
  EMPTY_JSON = "[]"

  def setup
    @home = Dir.mktmpdir("qmd-hook-home")
    File.write(File.join(@home, "projects.yml"), "projects: {}\n")
  end

  def teardown
    FileUtils.rm_rf(@home)
  end

  def present = ->(*) { true }
  def absent  = ->(*) { false }
  def runner_returning(out) = ->(_args) { [out, true] }

  def test_noop_when_no_tools_present
    out = QmdHook.run(prompt: "build a qmd hook for plastic", cwd: "/tmp", plastic_home: @home,
                      runner: runner_returning(HITS_JSON), detector: absent, serena_detector: absent)
    assert_nil out
  end

  def test_noop_when_prompt_too_short_and_no_tools
    out = QmdHook.run(prompt: "yes", cwd: "/tmp", plastic_home: @home,
                      runner: runner_returning(HITS_JSON), detector: absent, serena_detector: absent)
    assert_nil out
  end

  def test_noop_on_bare_continue_and_no_tools
    out = QmdHook.run(prompt: "continue", cwd: "/tmp", plastic_home: @home,
                      runner: runner_returning(HITS_JSON), detector: absent, serena_detector: absent)
    assert_nil out
  end

  def test_serena_only_emits_serena_mandate_without_qmd
    out = QmdHook.run(prompt: "navigate the codebase for a symbol", cwd: "/tmp", plastic_home: @home,
                      runner: runner_returning(HITS_JSON), detector: absent, serena_detector: present)
    assert_includes out, "MUST use Serena"
    refute_includes out, "MUST use QMD"
    refute_includes out, "Related / prior Plastic intents"
  end

  def test_qmd_mandate_on_short_prompt_skips_hit_search
    out = QmdHook.run(prompt: "yes", cwd: "/tmp", plastic_home: @home,
                      runner: runner_returning(EMPTY_JSON), detector: present, serena_detector: absent)
    assert_includes out, "MUST use QMD"
    refute_includes out, "Related / prior Plastic intents"
  end

  def test_injects_hits_and_mandate_when_above_threshold
    out = QmdHook.run(prompt: "enforce plastic supremacy across stores", cwd: "/tmp", plastic_home: @home,
                      runner: runner_returning(HITS_JSON), detector: present, serena_detector: absent)
    assert_includes out, "Related / prior Plastic intents"
    assert_includes out, "Enforce Plastic supremacy"
    assert_includes out, "81%"
    assert_includes out, "MUST use QMD", "qmd mandate line must be present"
  end

  def test_mandate_only_when_no_hits
    out = QmdHook.run(prompt: "some unrelated substantive prompt here", cwd: "/tmp", plastic_home: @home,
                      runner: runner_returning(EMPTY_JSON), detector: present, serena_detector: absent)
    refute_includes out, "Related / prior Plastic intents"
    assert_includes out, "MUST use QMD"
  end

  def test_serena_line_only_when_serena_detector_true
    with_serena = QmdHook.run(prompt: "some unrelated substantive prompt here", cwd: "/tmp", plastic_home: @home,
                              runner: runner_returning(EMPTY_JSON), detector: present, serena_detector: present)
    assert_includes with_serena, "MUST use Serena"

    without_serena = QmdHook.run(prompt: "some unrelated substantive prompt here", cwd: "/tmp", plastic_home: @home,
                                 runner: runner_returning(EMPTY_JSON), detector: present, serena_detector: absent)
    refute_includes without_serena, "MUST use Serena"
  end

  def test_nil_when_neither_tool_present
    out = QmdHook.run(prompt: "some unrelated substantive prompt here", cwd: "/tmp", plastic_home: @home,
                      runner: runner_returning(EMPTY_JSON), detector: absent, serena_detector: absent)
    assert_nil out
  end

  def test_executable_noops_when_no_tools_present
    require "open3"
    require "json"
    require "rbconfig"
    ruby = RbConfig.ruby
    script = File.expand_path("../scripts/hook-qmd-search", __dir__)
    input = JSON.generate("user_prompt" => "build a qmd hook for plastic stores")
    # PATH limited to system dirs (no qmd, no serena) and cwd is the tmpdir home
    # (no `.serena` ancestor), so neither tool is present -> no output, exit 0.
    # Launch ruby by absolute path so it does not depend on PATH; run from @home
    # so the script's Dir.pwd serena marker walk finds nothing.
    out, _err, status = Open3.capture3(
      { "PATH" => "/usr/bin:/bin" }, ruby, script, @home,
      chdir: @home, stdin_data: input
    )
    assert status.success?, "hook must exit 0 when no tools present"
    assert_equal "", out.strip, "hook must emit nothing when no tools present"
  end
end
