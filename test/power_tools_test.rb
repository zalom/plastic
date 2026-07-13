require "minitest/autorun"
require "tmpdir"
require "fileutils"
require_relative "../scripts/lib/power_tools"

class PowerToolsTest < Minitest::Test
  def present = ->(*) { true }
  def absent  = ->(*) { false }

  # --- mandate ---

  def test_mandate_qmd_only
    out = PowerTools.mandate(cwd: "/tmp", qmd_detector: present, serena_detector: absent,
                             enola_detector: absent)
    assert_includes out, "QMD is available"
    refute_includes out, "Serena"
  end

  def test_mandate_serena_only
    out = PowerTools.mandate(cwd: "/tmp", qmd_detector: absent, serena_detector: present,
                             enola_detector: absent)
    assert_includes out, "Serena is available"
    refute_includes out, "QMD is available"
  end

  def test_mandate_both_is_a_single_combined_line
    out = PowerTools.mandate(cwd: "/tmp", qmd_detector: present, serena_detector: present,
                             enola_detector: absent)
    assert_includes out, "QMD"
    assert_includes out, "Serena"
    refute_includes out, "\n"
    assert_equal 1, out.lines.count
  end

  # Intent 108, D8: the injections are recommendations, not obligations.
  def test_mandate_is_a_recommendation_not_an_obligation
    out = PowerTools.mandate(cwd: "/tmp", qmd_detector: present, serena_detector: present,
                             enola_detector: absent)
    refute_includes out, "MANDATORY"
    refute_includes out, "MUST"
    assert_includes out, "qmd"
    assert_includes out, "Serena"
  end

  def test_mandate_neither_is_nil
    out = PowerTools.mandate(cwd: "/tmp", qmd_detector: absent, serena_detector: absent,
                             enola_detector: absent)
    assert_nil out
  end

  # --- mandate: Enola composition (intent 187) ---

  def test_mandate_enola_only
    out = PowerTools.mandate(cwd: "/tmp", qmd_detector: absent, serena_detector: absent,
                             enola_detector: present)
    assert_includes out, "Enola is available"
    refute_includes out, "Serena"
    refute_includes out, "QMD is available"
  end

  def test_mandate_enola_and_qmd_is_a_single_combined_line
    out = PowerTools.mandate(cwd: "/tmp", qmd_detector: present, serena_detector: absent,
                             enola_detector: present)
    assert_includes out, "QMD"
    assert_includes out, "Enola"
    refute_includes out, "Serena"
    refute_includes out, "\n"
    assert_equal 1, out.lines.count
  end

  # Enola-first: one code-navigation slot, Enola wins when both are present.
  def test_mandate_enola_and_serena_names_only_enola
    out = PowerTools.mandate(cwd: "/tmp", qmd_detector: absent, serena_detector: present,
                             enola_detector: present)
    assert_includes out, "Enola is available"
    refute_includes out, "Serena"
  end

  def test_mandate_all_three_names_qmd_and_enola_only
    out = PowerTools.mandate(cwd: "/tmp", qmd_detector: present, serena_detector: present,
                             enola_detector: present)
    assert_includes out, "QMD"
    assert_includes out, "Enola"
    refute_includes out, "Serena"
    refute_includes out, "\n"
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

  # --- enola? (intent 187) ---

  def test_enola_true_via_injected_marker_finder
    assert PowerTools.enola?(cwd: "/tmp", path_probe: absent,
                             marker_finder: ->(_cwd) { true })
  end

  def test_enola_true_via_real_ancestor_marker
    Dir.mktmpdir("enola-marker") do |root|
      FileUtils.mkdir_p(File.join(root, ".enola"))
      nested = File.join(root, "a", "b", "c")
      FileUtils.mkdir_p(nested)
      assert PowerTools.enola?(cwd: nested, path_probe: absent)
    end
  end

  def test_enola_true_via_injected_path_probe
    Dir.mktmpdir("enola-nomarker") do |dir|
      assert PowerTools.enola?(cwd: dir, path_probe: -> { true })
    end
  end

  def test_enola_false_when_no_marker_and_not_on_path
    Dir.mktmpdir("enola-none") do |dir|
      refute PowerTools.enola?(cwd: dir, path_probe: absent)
    end
  end
end
