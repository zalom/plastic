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

  def test_noop_when_qmd_absent
    out = QmdHook.run(prompt: "build a qmd hook for plastic", cwd: "/tmp", plastic_home: @home,
                      runner: runner_returning(HITS_JSON), detector: absent)
    assert_nil out
  end

  def test_noop_when_prompt_too_short
    out = QmdHook.run(prompt: "yes", cwd: "/tmp", plastic_home: @home,
                      runner: runner_returning(HITS_JSON), detector: present)
    assert_nil out
  end

  def test_noop_on_bare_continue
    out = QmdHook.run(prompt: "continue", cwd: "/tmp", plastic_home: @home,
                      runner: runner_returning(HITS_JSON), detector: present)
    assert_nil out
  end

  def test_injects_hits_and_reminder_when_above_threshold
    out = QmdHook.run(prompt: "enforce plastic supremacy across stores", cwd: "/tmp", plastic_home: @home,
                      runner: runner_returning(HITS_JSON), detector: present)
    assert_includes out, "Related / prior Plastic intents"
    assert_includes out, "Enforce Plastic supremacy"
    assert_includes out, "81%"
    assert_includes out, "query it", "reminder line must be present"
  end

  def test_reminder_only_when_no_hits
    out = QmdHook.run(prompt: "some unrelated substantive prompt here", cwd: "/tmp", plastic_home: @home,
                      runner: runner_returning(EMPTY_JSON), detector: present)
    refute_includes out, "Related / prior Plastic intents"
    assert_includes out, "query it"
  end

  def test_executable_noops_when_qmd_absent_from_path
    require "open3"
    require "json"
    require "rbconfig"
    ruby = RbConfig.ruby
    script = File.expand_path("../scripts/hook-qmd-search", __dir__)
    input = JSON.generate("user_prompt" => "build a qmd hook for plastic stores")
    # PATH limited to system dirs (no qmd) -> detector false -> no output, exit 0.
    # Launch ruby by absolute path so it does not depend on PATH.
    out, _err, status = Open3.capture3({ "PATH" => "/usr/bin:/bin" }, ruby, script, @home, stdin_data: input)
    assert status.success?, "hook must exit 0 when qmd absent"
    assert_equal "", out.strip, "hook must emit nothing when qmd absent"
  end
end
