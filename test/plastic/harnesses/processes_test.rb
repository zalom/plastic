# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../../scripts/lib/plastic/harnesses/processes"

class HarnessProcessesTest < Plastic::TestCase
  def proc_root(table)
    root = File.join(@home, "proc")
    table.each do |pid, (name, parent)|
      FileUtils.mkdir_p(File.join(root, pid.to_s))
      File.write(File.join(root, pid.to_s, "stat"), "#{pid} (#{name}) S #{parent} 1 1 0 -1\n")
    end
    root
  end

  def test_the_ancestors_are_named_nearest_first
    root = proc_root(40 => ["ruby", 30], 30 => ["zsh", 20], 20 => ["codex", 10], 10 => ["claude", 1])

    assert_equal %w[zsh codex claude], Plastic::Harnesses::Processes.new(root:, pid: 40).ancestors
  end

  def test_a_process_name_with_spaces_and_parentheses_is_read_whole
    root = proc_root(40 => ["ruby", 30], 30 => ["my (odd) name", 1])

    assert_equal ["my (odd) name"], Plastic::Harnesses::Processes.new(root:, pid: 40).ancestors
  end

  def test_with_no_process_folder_there_are_no_ancestors
    assert_empty Plastic::Harnesses::Processes.new(root: File.join(@home, "none"), pid: 40).ancestors
  end

  def test_none_has_no_ancestors
    assert_empty Plastic::Harnesses::Processes.none.ancestors
  end
end
