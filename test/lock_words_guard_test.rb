# frozen_string_literal: true

require_relative "test_helper"

# No lock is left to name: the claim of a node replaced it, so no command page, step or guide says a lock is released.
class LockWordsGuardTest < Plastic::TestCase
  ROOT = File.expand_path("..", __dir__)

  def text(path) = File.read(File.join(ROOT, path))

  def test_intent_end_and_abandon_name_no_lock
    files = %w[lib/plastic/workflows/code/intent/end.rb lib/plastic/workflows/code/intent/abandon.rb
      docs/reference/commands/intent-end/README.md docs/reference/commands/intent-abandon/README.md]

    assert_empty(files.select { |path| text(path).match?(/\block\b/i) })
  end

  def test_the_contributing_guide_uses_node_renew_as_its_nested_example
    guide = text("CONTRIBUTING.md")

    refute_match(/intent lock/i, guide)
    assert_includes guide, "Commands::Node::Renew"
  end
end
