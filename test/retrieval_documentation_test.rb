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

  def test_tools_guide_says_the_architecture_commands_only_instruct_the_agent
    content = File.read(File.join(ROOT, "docs/help/tools.md"))

    assert_includes content, "plastic architecture refresh"
    assert_includes content, "print instructions only"
    assert_includes content, "does not run Enola"
  end

  def test_examples_use_context_from
    readme = File.read(File.join(ROOT, "README.md"))

    assert_includes readme, "intent context 12 --from selected-context.json"
  end

  private

  def public_docs
    %w[
      README.md
    ]
  end
end
