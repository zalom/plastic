# frozen_string_literal: true

require "stringio"
require_relative "../../command_reference_helper"

class CommandReferenceCliTest < Minitest::Test
  Built = Struct.new(:files)

  def run_cli(root, files, *argv)
    out = StringIO.new
    code = CommandReference::CLI.new(argv, root:, out:, build: Built.new(files)).run
    [code, out.string]
  end

  def with_root
    Dir.mktmpdir do |root|
      FileUtils.mkdir_p(File.join(root, "docs/reference/commands/gone"))
      File.write(File.join(root, "docs/reference/commands/gone/README.md"), "left over")
      yield root
    end
  end

  def test_a_build_writes_every_page_and_removes_a_folder_the_build_no_longer_holds
    with_root do |root|
      code, = run_cli(root, { "docs/reference/commands/README.md" => "index" })

      assert_equal 0, code
      assert_equal "index", File.read(File.join(root, "docs/reference/commands/README.md"))
      refute File.exist?(File.join(root, "docs/reference/commands/gone/README.md"))
    end
  end

  def test_check_names_the_stale_paths_and_exits_1
    with_root do |root|
      code, out = run_cli(root, { "docs/reference/commands/README.md" => "index" }, "--check")

      assert_equal 1, code
      assert_includes out, "docs/reference/commands/README.md"
      assert_includes out, "docs/reference/commands/gone/README.md"
    end
  end

  def test_check_exits_0_when_the_pages_are_current
    with_root do |root|
      files = { "docs/reference/commands/README.md" => "index" }
      run_cli(root, files)

      assert_equal [0, ""], run_cli(root, files, "--check")
    end
  end
end
