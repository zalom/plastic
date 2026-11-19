# frozen_string_literal: true

require_relative "test_helper"
require "json"
require "tmpdir"
require "yaml"
require_relative "support/child_process"

# .rubocop_todo.yml and .reek.yml excuse the offenses of older code. An entry
# stays only while the tool still reports the offense it excuses, so each list
# shrinks as the code is fixed and never hides an offense that is gone.
class ExcusedOffensesGuardTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)

  def test_every_rubocop_todo_entry_names_an_offense_rubocop_still_reports
    todo = YAML.load_file(File.join(ROOT, ".rubocop_todo.yml"))
    excused = todo.flat_map { |cop, settings| settings.fetch("Exclude", []).map { |file| [cop, file] } }

    assert_empty excused - rubocop_offenses(todo.keys, excused.map(&:last).uniq)
  end

  def test_every_reek_exclude_names_a_smell_reek_still_reports
    reek = YAML.load_file(File.join(ROOT, ".reek.yml"))
    excused = reek.fetch("detectors").flat_map { |smell, settings| settings.fetch("exclude", []).map { |context| [smell, context] } }

    assert_empty excused - reek_smells(reek)
  end

  private

  def rubocop_offenses(cops, files)
    report = tool("rubocop", "--config", ".rubocop.yml", "--format", "json", "--only", cops.join(","), *files.select { |file| File.exist?(File.join(ROOT, file)) })
    report.fetch("files").flat_map { |file| file.fetch("offenses").map { |offense| [offense.fetch("cop_name"), file.fetch("path")] } }
  end

  def reek_smells(reek)
    Dir.mktmpdir("reek-config") do |dir|
      config = File.join(dir, "reek.yml")
      File.write(config, reek.merge("detectors" => reek.fetch("detectors").transform_values { |settings| without_excludes(settings) }).to_yaml)
      tool("reek", "--config", config, "--format", "json", ".").map { |smell| [smell.fetch("smell_type"), smell.fetch("context")] }
    end
  end

  def without_excludes(settings)
    rest = settings.except("exclude")
    rest.empty? ? { "enabled" => true } : rest
  end

  def tool(*command)
    output, = ChildProcess.capture2("bundle", "exec", *command, chdir: ROOT)
    JSON.parse(output)
  end
end
