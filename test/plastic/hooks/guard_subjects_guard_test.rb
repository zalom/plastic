# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../../lib/plastic/hooks/guard_verdict"

# The guard refuses an agent write to every core file and every project record that layout.yml names. The subjects
# are read from layout.yml on disk, so a core file added there is guarded with no change here.
class GuardSubjectsGuardTest < Plastic::TestCase
  LAYOUT = YAML.safe_load_file(File.expand_path("../../../lib/plastic/layout.yml", __dir__))

  def core_files = LAYOUT.fetch("files").values.map { |entry| entry.fetch("name") }

  def project_records = LAYOUT.fetch("project_records")

  def test_every_core_file_of_the_layout_is_refused
    intent = open_intent
    verdict = Plastic::Hooks::GuardVerdict.new(home: @plastic_home, cwd: Dir.pwd)

    refute_empty core_files
    core_files.each { |name| refute_nil verdict.reason("Write", { file_path: store_path("#{intent.dir}/#{name}") }), name }
  end

  def test_every_project_record_folder_of_the_layout_is_refused
    verdict = Plastic::Hooks::GuardVerdict.new(home: @plastic_home, cwd: Dir.pwd)

    refute_empty project_records
    project_records.each { |folder| refute_nil verdict.reason("Write", { file_path: File.join(Dir.pwd, folder, "a.md") }), folder }
  end
end
