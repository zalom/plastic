# encoding: UTF-8
# frozen_string_literal: true

require "minitest/autorun"

# docs/reference/harness-adapters.md carries an honest harness support matrix
# and makes no false provenance claims. Read the file, assert on its prose.
class HarnessSupportDocsTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)
  ADAPTERS_DOC = File.join(ROOT, "docs", "reference", "harness-adapters.md")
  README = File.join(ROOT, "README.md")

  def adapters_doc_text
    File.read(ADAPTERS_DOC)
  end

  def readme_text
    File.read(README)
  end

  def harness_support_section
    text = adapters_doc_text
    start = text.index("## Harness support")
    raise "## Harness support heading not found" unless start
    rest = text[start..]
    next_heading = rest.index("\n## ", 1)
    next_heading ? rest[0...next_heading] : rest
  end

  def test_adapter_doc_no_longer_claims_no_codex_installed
    refute_includes adapters_doc_text, "the owner has no Codex installed"
  end

  def test_adapter_doc_carries_a_support_matrix
    section = harness_support_section
    assert_includes adapters_doc_text, "## Harness support"
    assert_includes section, "Claude Code"
    assert_includes section, "Codex CLI"
    assert_includes section, "Hermes"
  end

  # The doc counts the full residue of Claude-specific lines on a Codex install:
  # the 4 hook-launcher lines, which are also the only entries
  # codex_install_content_test's allowlist carries. Pins the claim so it cannot
  # silently understate the residue.
  def test_support_matrix_discloses_the_full_residue_count
    section = harness_support_section.gsub(/\s+/, " ")
    assert_includes section, "Four lines still speak Claude Code afterward"
    assert_includes section, "four instruction lines that name Claude's hook launcher directory"
    assert_includes section, "left the installed tree in 2.0"
  end

  def test_support_matrix_names_no_plugin_install_path
    section = harness_support_section.downcase
    refute_includes section, "plugin"
    refute_includes section, "marketplace"
  end

  def per_agent_model_mapping_section
    text = adapters_doc_text
    start = text.index("### Per-agent model mapping")
    raise "### Per-agent model mapping heading not found" unless start
    rest = text[start..]
    next_heading = rest.index("\n### ", 1)
    next_heading ? rest[0...next_heading] : rest
  end

  # check_agent_model_drift_codex reads `model` and `model_reasoning_effort` as two
  # separate lines (codex_agent_toml_model_fields) and compares both against their
  # resolved defaults. The doc must describe both fields, not the effort line only.
  def test_model_drift_doc_describes_both_fields_not_effort_only
    section = per_agent_model_mapping_section.gsub(/\s+/, " ")
    assert_includes section, "reads the `model` and `model_reasoning_effort` lines as two separate values"
    assert_includes section, "compares the model value against the tier's resolved Codex model id"
    assert_includes section, "intent 216"
    refute_includes section, "compares each file's `model_reasoning_effort` line against the tier default, honoring"
  end

  def test_readme_has_no_doubled_and
    refute_includes readme_text, "and and"
  end

  def test_readme_does_not_claim_a_native_hermes_installer
    normalized = readme_text.gsub(/\s+/, " ")
    normalized.split(/(?<=[.!?])\s+/).each do |sentence|
      if sentence.include?("Hermes")
        refute_match(/Native installer/i, sentence, "README must not claim a native installer for Hermes")
      end
    end
    assert_includes readme_text, "docs/reference/harness-adapters.md"
  end
end
