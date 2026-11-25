# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../../lib/plastic/hooks/guard_verdict"

# How the guard reads a shell command: the folder each cd moves to, and the inline scripts of the interpreters. A
# program file is not read.
class GuardVerdictShellTest < Plastic::TestCase
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

  def shell(command) = verdict.reason("Bash", { command: })

  def test_a_relative_write_after_a_cd_into_the_intent_folder_is_refused
    folder = path("")

    ["cd #{folder} && echo x > spec.md", "cd '#{folder}'; rm -f spec.md", "cd #{File.dirname(folder)} && touch #{File.basename(folder)}/spec.md",
      "cd /tmp && cd #{folder} && sed -i '' 's/a/b/' outcome.md", "(cd #{folder} && echo x >| spec.md)",
      "cd #{folder} && ruby -e 'File.write(\"spec.md\", 1)'"].each do |command|
      refute_nil shell(command), command
    end
  end

  def test_a_cd_that_leaves_the_intent_folder_is_followed
    folder = path("")

    ["cd #{folder} && echo x > resources/tmp/a.md", "cd #{folder} && cd /tmp && echo x > spec.md",
      "(cd #{folder} && cat spec.md); echo x > spec.md", "cd #{folder} && cat spec.md > /tmp/spec.md"].each do |command|
      assert_nil shell(command), command
    end
  end

  def test_a_cd_with_no_folder_goes_home
    home = File.dirname(@plastic_home)
    relative = path("spec.md").delete_prefix("#{home}/")
    guard = Plastic::Hooks::GuardVerdict.new(home: @plastic_home, cwd: @project, user_home: home)

    refute_nil guard.reason("Bash", { command: "cd && rm #{relative}" })
    assert_nil guard.reason("Bash", { command: "cd - && rm #{relative}" })
  end

  def test_each_inline_script_form_that_names_a_core_file_is_refused
    spec = path("spec.md")

    ["ruby -ne 'File.write(\"#{spec}\", 1)' /dev/null", "python3 -Ic 'open(\"#{spec}\", \"w\")'", "node --eval 'fs.writeFileSync(\"#{spec}\", 1)'",
      "bash -lc 'echo x > #{spec}'", "/usr/bin/python3.12 -c 'open(\"#{spec}\", \"w\")'", "echo 'File.write(\"#{spec}\", 1)' | ruby",
      "perl -e 'open(F, \">#{spec}\")'"].each do |command|
      refute_nil shell(command), command
    end
  end

  def test_a_program_file_is_not_read
    assert_nil shell("ruby tool.rb #{path("spec.md")}")
  end
end
