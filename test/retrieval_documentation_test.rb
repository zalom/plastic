# frozen_string_literal: true

require_relative "test_helper"
require_relative "support/child_process"

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
    commands = File.read(File.join(ROOT, "docs/usage/commands.md"))

    assert_includes commands, "intent context 12 --from selected-context.json"
  end

  KEPT_QMD_FILES = %w[
    CHANGELOG.md
    lib/plastic/installations/hook_registry.rb
    lib/plastic/installations/hook_ownership.rb
  ].freeze

  def test_no_shipped_file_names_qmd_outside_the_kept_places
    shipped = ChildProcess.capture2("git", "-C", ROOT, "ls-files").first.split("\n").reject { |path| path.start_with?("test/") }
    named = (shipped - KEPT_QMD_FILES).select do |path|
      file = File.join(ROOT, path)
      File.file?(file) && File.read(file).force_encoding("UTF-8").scrub.match?(/qmd/i)
    end

    assert_empty named
  end

  def test_tools_help_has_no_qmd_section_and_still_names_enola
    content = File.read(File.join(ROOT, "docs/help/tools.md"))

    refute_match(/qmd/i, content)
    assert_includes content, "Enola"
  end

  def test_the_installed_plastic_template_has_no_qmd
    refute_match(/qmd/i, File.read(File.join(ROOT, "PLASTIC.md")))
  end

  private

  def public_docs
    %w[
      README.md
    ]
  end
end
