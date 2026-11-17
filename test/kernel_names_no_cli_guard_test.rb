# frozen_string_literal: true

require_relative "test_helper"

class KernelNamesNoCliGuardTest < Minitest::Test
  LIB = File.expand_path("../lib", __dir__)
  SHELL = %w[plastic/cli.rb plastic/cli/ plastic/commands/ plastic/hook.rb plastic/routine.rb plastic/routine/].freeze
  CLI_NAME = /\bCLI::/

  def kernel_files
    Dir.glob(File.join(LIB, "**", "*.rb")).reject do |path|
      relative = path.delete_prefix("#{LIB}/")
      SHELL.any? { |shell| relative == shell || relative.start_with?(shell) && shell.end_with?("/") }
    end
  end

  def test_the_kernel_files_are_read_from_the_disk
    refute_empty kernel_files
  end

  def test_no_file_outside_the_shell_names_cli
    hits = kernel_files.select { |path| File.read(path, encoding: "UTF-8").match?(CLI_NAME) }

    assert_empty hits.map { |path| path.delete_prefix("#{LIB}/") }
  end
end
