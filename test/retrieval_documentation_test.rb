# frozen_string_literal: true

require "minitest/autorun"

class RetrievalDocumentationTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)

  def test_public_docs_describe_only_the_retrieval_commands
    public_docs.each do |path|
      content = File.read(File.join(ROOT, path))

      refute_match(/plastic index|search --ask|plastic query SQL/, content, path)
    end
  end

  def test_search_guide_has_the_current_scope_limit_and_read_contract
    content = File.read(File.join(ROOT, "docs/guide/getting-started/search-commands.md"))

    assert_includes content, "--source-project SLUG"
    assert_includes content, "default limit is 20"
    assert_includes content, "does not write"
  end

  def test_tools_guide_explains_explicit_enola_refresh_and_provenance
    content = File.read(File.join(ROOT, "docs/help/tools.md"))

    assert_includes content, "plastic architecture refresh"
    assert_includes content, "provenance"
    assert_includes content, "does not refresh Enola"
  end

  def test_examples_use_context_from_and_qualified_document_references
    readme = File.read(File.join(ROOT, "README.md"))
    guide = File.read(File.join(ROOT, "docs/guide/getting-started/search-commands.md"))

    assert_includes readme, "intent context 12 --from selected-context.json"
    assert_includes guide, "Fetches a qualified document."
    refute_includes guide, "current or revision-qualified"
  end

  private

  def public_docs
    %w[
      README.md
      docs/guide/getting-started/search-commands.md
      docs/guide/getting-started/ask-a-question.md
      docs/guide/getting-started/what-plastic-covers.md
    ]
  end
end
