# encoding: UTF-8
# frozen_string_literal: true

require "minitest/autorun"

# Intent 239: the false provenance claims are corrected, and the honest support matrix
# lands in docs/reference/harness-adapters.md. Modeled on test/harness_adapters_doc_test.rb:
# read the file, assert on its prose. A new file so it cannot collide with that one.
class HarnessSupportDocsTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)
  ENVELOPE = File.join(ROOT, "scripts", "lib", "apply_patch_envelope.rb")
  ADAPTERS_DOC = File.join(ROOT, "docs", "reference", "harness-adapters.md")
  README = File.join(ROOT, "README.md")

  def envelope_text
    File.read(ENVELOPE)
  end

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

  def test_parser_comment_no_longer_claims_the_grammar_is_unsourced
    refute_includes envelope_text, "not primary-sourced"
    refute_includes envelope_text, "the owner has none installed"
    assert_includes envelope_text, "test/fixtures/codex-v4a-grammar.txt"
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

  # Intent 239 review: the published note previously said only "Four instruction
  # lines... are left as they are", undercounting the real residue. The full count on
  # a Codex install is 11: the 4 hook-launcher lines (D5), 2 CLAUDE_PLUGIN_ROOT lines
  # in the skill-authoring reference (D3), 1 line in the shared
  # _active-intent-gate.md fragment (D8), and 4 lines inside skill evals/evals.json
  # fixtures (D7). Pins the corrected claim so it cannot silently regress to
  # understating the residue again.
  def test_support_matrix_discloses_the_full_residue_count
    section = harness_support_section.gsub(/\s+/, " ")
    assert_includes section, "Eleven lines still speak Claude Code afterward"
    assert_includes section, "four instruction lines that name Claude's hook launcher directory"
    assert_includes section, "two lines in a skill-authoring reference"
    assert_includes section, "_active-intent-gate.md"
    assert_includes section, "four lines inside skill `evals/evals.json` fixtures"
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

  # Intent 239a: intent 216 (commit b6ad017) landed after intent 239 delivered and widened
  # check_agent_model_drift_codex to read `model` and `model_reasoning_effort` as two
  # separate lines (codex_agent_toml_model_fields), comparing both against their resolved
  # defaults. The doc previously said the check only reads the `model_reasoning_effort`
  # line, which was true before intent 216 but is stale now: the old single-value extractor
  # preferred effort via an `||` fallback and never opened the model line, so a drifted
  # per-role model id passed silently. Pins the corrected claim so a revert to the old
  # wording fails this test (see RED proof in the intent 239 outcome).
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
