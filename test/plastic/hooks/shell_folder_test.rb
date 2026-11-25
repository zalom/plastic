# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../../lib/plastic/hooks/shell_folder"

# The folder a shell command runs in, as its cd words and subshells move it.
class ShellFolderTest < Minitest::Test
  def setup
    @folder = Plastic::Hooks::ShellFolder.new
  end

  def test_a_word_stays_as_it_is_before_any_cd
    assert_equal "spec.md", @folder.resolve("spec.md")
  end

  def test_a_cd_joins_a_relative_word_and_keeps_a_rooted_one
    @folder.change("/a")
    @folder.change("b")

    assert_equal ["/a/b/spec.md", "/c", "~/d", "$HOME/e"], %w[spec.md /c ~/d $HOME/e].map { |word| @folder.resolve(word) }
  end

  def test_a_subshell_keeps_its_cd_to_itself
    @folder.change("/a")
    @folder.enter
    @folder.change("/b")
    @folder.leave

    assert_equal "/a/x", @folder.resolve("x")
  end

  def test_an_unmatched_end_of_a_subshell_keeps_the_folder
    @folder.change("/a")
    @folder.leave

    assert_equal "/a/x", @folder.resolve("x")
  end
end
