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

  def test_support_matrix_names_no_plugin_install_path
    section = harness_support_section.downcase
    refute_includes section, "plugin"
    refute_includes section, "marketplace"
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
