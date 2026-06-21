require "minitest/autorun"
require "tmpdir"
require "fileutils"
require_relative "../scripts/lib/power_tools"

class PowerToolsTest < Minitest::Test
  def present = ->(*) { true }
  def absent  = ->(*) { false }

  # --- mandate ---

  def test_mandate_qmd_only
    out = PowerTools.mandate(cwd: "/tmp", qmd_detector: present, serena_detector: absent)
    assert_includes out, "MANDATORY"
    assert_includes out, "MUST use QMD"
    refute_includes out, "Serena"
  end

  def test_mandate_serena_only
    out = PowerTools.mandate(cwd: "/tmp", qmd_detector: absent, serena_detector: present)
    assert_includes out, "MANDATORY"
    assert_includes out, "MUST use Serena"
    refute_includes out, "use QMD"
  end

  def test_mandate_both
    out = PowerTools.mandate(cwd: "/tmp", qmd_detector: present, serena_detector: present)
    assert_includes out, "MUST use QMD"
    assert_includes out, "MUST use Serena"
    assert_equal 2, out.lines.count
  end

  def test_mandate_neither_is_nil
    out = PowerTools.mandate(cwd: "/tmp", qmd_detector: absent, serena_detector: absent)
    assert_nil out
  end

  # --- qmd? ---

  def test_qmd_present_and_absent
    assert PowerTools.qmd?(detector: present)
    refute PowerTools.qmd?(detector: absent)
  end

  # --- serena? ---

  def test_serena_true_via_injected_marker_finder
    assert PowerTools.serena?(cwd: "/tmp", path_probe: absent,
                              marker_finder: ->(_cwd) { true })
  end

  def test_serena_true_via_real_ancestor_marker
    Dir.mktmpdir("serena-marker") do |root|
      FileUtils.mkdir_p(File.join(root, ".serena"))
      nested = File.join(root, "a", "b", "c")
      FileUtils.mkdir_p(nested)
      assert PowerTools.serena?(cwd: nested, path_probe: absent)
    end
  end

  def test_serena_true_via_injected_path_probe
    Dir.mktmpdir("serena-nomarker") do |dir|
      assert PowerTools.serena?(cwd: dir, path_probe: -> { true })
    end
  end

  def test_serena_false_when_no_marker_and_not_on_path
    Dir.mktmpdir("serena-none") do |dir|
      refute PowerTools.serena?(cwd: dir, path_probe: absent)
    end
  end
end
