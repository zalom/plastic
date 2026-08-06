require "minitest/autorun"
require "tmpdir"
require "fileutils"
require_relative "../scripts/lib/qmd_hook"

class QmdHookTest < Minitest::Test
  def setup
    @home = Dir.mktmpdir("qmd-hook-home")
    File.write(File.join(@home, "projects.yml"), "projects: {}\n")
  end

  def teardown
    FileUtils.rm_rf(@home)
  end

  def present = ->(*) { true }
  def absent  = ->(*) { false }

  def test_noop_when_no_tools_present
    out = QmdHook.run(cwd: "/tmp", detector: absent, serena_detector: absent,
                      enola_detector: absent)
    assert_nil out
  end

  def test_qmd_only_emits_the_qmd_line
    out = QmdHook.run(cwd: "/tmp", detector: present, serena_detector: absent,
                      enola_detector: absent)
    assert_includes out, "QMD is available"
  end

  def test_serena_only_emits_serena_line_without_qmd
    out = QmdHook.run(cwd: "/tmp", detector: absent, serena_detector: present,
                      enola_detector: absent)
    assert_includes out, "Serena is available"
    refute_includes out, "QMD is available"
  end

  def test_serena_line_only_when_serena_detector_true
    with_serena = QmdHook.run(cwd: "/tmp", detector: present, serena_detector: present,
                              enola_detector: absent)
    assert_includes with_serena, "Serena"

    without_serena = QmdHook.run(cwd: "/tmp", detector: present, serena_detector: absent,
                                 enola_detector: absent)
    refute_includes without_serena, "Serena"
  end

  # --- Enola composition (intent 187) ---

  def test_enola_only_emits_enola_line_without_serena_or_qmd
    out = QmdHook.run(cwd: "/tmp", detector: absent, serena_detector: absent,
                      enola_detector: present)
    assert_includes out, "Enola is available"
    refute_includes out, "Serena"
    refute_includes out, "QMD is available"
  end

  def test_enola_first_suppresses_serena_when_both_present
    out = QmdHook.run(cwd: "/tmp", detector: absent, serena_detector: present,
                      enola_detector: present)
    assert_includes out, "Enola is available"
    refute_includes out, "Serena"
  end

  # --- Intent 246: the retrieval injection is gone ---

  # The removed block could emit exactly two shapes: the header line, and one
  # percentage-scored hit line per hit. Their absence across every tool
  # combination is this intent's behavior contract, so it is asserted directly
  # rather than inferred from the code being deleted.
  def test_no_retrieval_hits_are_ever_injected
    [absent, present].each do |qmd|
      [absent, present].each do |serena|
        [absent, present].each do |enola|
          out = QmdHook.run(cwd: "/tmp", detector: qmd, serena_detector: serena,
                            enola_detector: enola).to_s
          refute_includes out, "Related / prior Plastic intents"
          refute_match(/\[\d+%\]/, out)
        end
      end
    end
  end

  def test_executable_noops_when_no_tools_present
    require "open3"
    require "json"
    require "rbconfig"
    ruby = RbConfig.ruby
    script = File.expand_path("../scripts/hook-power-tools", __dir__)
    input = JSON.generate("user_prompt" => "build a hook for plastic stores")
    # PATH limited to system dirs (no qmd, no serena, no enola) and cwd is the
    # tmpdir home (no `.serena`/`.enola` ancestor), so no tool is present -> no
    # output, exit 0. Launch ruby by absolute path so it does not depend on
    # PATH; run from @home so the script's Dir.pwd marker walks find nothing.
    out, _err, status = Open3.capture3(
      { "PATH" => "/usr/bin:/bin" }, ruby, script,
      chdir: @home, stdin_data: input
    )
    assert status.success?, "hook must exit 0 when no tools present"
    assert_equal "", out.strip, "hook must emit nothing when no tools present"
  end
end
