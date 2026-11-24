# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../../lib/plastic/hooks/guard_verdict"

# Which agent writes the guard refuses: the core files of a store, every file of a closed intent, a folder no intent
# owns and the intent records of a project tree. The resources folder of an open intent stays open.
class GuardVerdictTest < Plastic::TestCase
  include LifecycleHelper

  def setup
    super
    @intent = open_intent
    @project = Dir.mktmpdir("guard-project")
  end

  def teardown
    FileUtils.rm_rf(@project)
    super
  end

  def verdict = Plastic::Hooks::GuardVerdict.new(home: @plastic_home, cwd: @project)

  def path(name) = store_path("#{@intent.dir}/#{name}")

  def write_tool(file) = verdict.reason("Write", { file_path: file, content: "x" })

  def shell(command) = verdict.reason("Bash", { command: })

  def test_a_write_to_the_spec_of_an_open_intent_is_refused_and_names_its_command
    reason = write_tool(path("spec.md"))

    assert_includes reason, "plastic intent spec"
    assert_includes reason, "Only the resources/ folder of an open intent is open to the agent."
  end

  def test_a_write_under_the_resources_folder_of_an_open_intent_passes
    assert_nil write_tool(path("resources/tmp/notes.md"))
  end

  def test_an_edit_of_the_outcome_is_refused
    refute_nil verdict.reason("Edit", { file_path: path("outcome.md"), old_string: "a", new_string: "b" })
  end

  def test_a_notebook_edit_in_the_store_is_refused
    refute_nil verdict.reason("NotebookEdit", { notebook_path: path("graph.json") })
  end

  def test_a_file_of_a_closed_intent_is_refused_even_under_resources
    write("#{@intent.dir}/outcome.md", "# Outcome\n\nDropped.\n\n## Verification\n- Abandoned: dropped because the need went away\n")
    cli("store", "sync", "up")
    cli("intent", "abandon", "1")

    assert_includes write_tool(path("resources/tmp/notes.md")), "intent 1 is abandoned"
  end

  def test_a_folder_no_intent_owns_is_refused
    assert_includes write_tool(store_path("store/9--made-by-hand/intent.md")), "plastic intent new"
  end

  def test_the_store_index_and_a_database_are_refused
    refute_nil write_tool(store_path("store/index.json"))
    refute_nil write_tool(store_path("work_graph.db"))
  end

  def test_an_intent_record_in_the_project_tree_is_refused
    assert_includes write_tool(File.join(@project, "docs/specs/login.md")), "plastic intent new"
    refute_nil write_tool(File.join(@project, "docs/plans/login.md"))
  end

  def test_a_project_file_outside_the_records_passes
    assert_nil write_tool(File.join(@project, "lib/login.rb"))
  end

  def test_a_relative_path_is_read_from_the_working_directory
    assert_nil verdict.reason("Write", { file_path: "docs/notes.md" })
    refute_nil verdict.reason("Write", { file_path: "docs/specs/notes.md" })
  end

  def test_each_shell_write_form_that_names_a_core_file_is_refused
    spec = path("spec.md")

    ["echo x > #{spec}", "echo x >> '#{spec}'", "echo x | tee #{spec}", "rm -f #{spec}", "mv #{spec} /tmp/spec.md",
      "cp /tmp/spec.md #{spec}", "touch #{spec}", "sed -i '' 's/a/b/' #{spec}", "dd if=/dev/zero of=#{spec}",
      "ruby -e 'File.write(\"#{spec}\", 1)'", "cd /tmp && FOO=1 rm #{spec}"].each do |command|
      refute_nil shell(command), command
    end
  end

  def test_a_script_given_on_standard_input_that_names_a_core_file_is_refused
    refute_nil shell("ruby <<'RUBY'\nFile.write(\"#{path("spec.md")}\", 1)\nRUBY")
  end

  def test_a_shell_read_of_a_core_file_passes
    spec = path("spec.md")

    ["cat #{spec}", "grep -n Goal #{spec}", "cp #{spec} /tmp/spec.md", "wc -l #{spec} > /tmp/count"].each do |command|
      assert_nil shell(command), command
    end
  end

  def test_a_home_path_in_the_shell_is_expanded
    home = File.dirname(@plastic_home)
    relative = path("spec.md").delete_prefix("#{home}/")

    refute_nil Plastic::Hooks::GuardVerdict.new(home: @plastic_home, cwd: @project, user_home: home).reason("Bash", { command: "rm ~/#{relative}" })
  end

  def test_a_patch_that_adds_or_updates_a_core_file_is_refused
    patch = "*** Begin Patch\n*** Update File: #{path("outcome.md")}\n@@\n-a\n+b\n*** End Patch\n"

    refute_nil verdict.reason("apply_patch", { command: patch })
    refute_nil verdict.reason("apply_patch", { input: patch.sub("Update", "Add") })
    assert_nil verdict.reason("apply_patch", { input: patch.sub(path("outcome.md"), path("resources/tmp/a.md")) })
  end

  def test_another_file_of_an_intent_folder_is_refused_outside_resources
    assert_includes write_tool(path("draft.md")), "only Plastic commands write files there"
  end

  def test_a_file_printed_from_the_rows_is_refused
    assert_includes write_tool(path("graph.json")), "Plastic prints it from the database rows"
  end

  def test_a_home_path_of_an_unknown_user_passes
    assert_nil shell("rm ~no-such-user-here/spec.md")
  end

  def test_a_store_with_no_index_owns_no_folder
    assert_includes write_tool(File.join(@plastic_home, "stores", "other", "store", "1--a", "spec.md")), "no intent owns"
  end

  def test_a_home_whose_stores_were_not_moved_keeps_its_global_store_under_store
    Dir.mktmpdir("guard-home") do |home|
      unmoved = Plastic::Hooks::GuardVerdict.new(home:, cwd: @project)

      refute_nil unmoved.reason("Write", { file_path: File.join(home, "store", "index.json") })
      assert_nil unmoved.reason("Write", { file_path: File.join(home, "notes.md") })
    end
  end

  def test_a_tool_that_writes_nothing_passes
    assert_nil verdict.reason("Read", { file_path: path("spec.md") })
  end
end
