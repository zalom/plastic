# frozen_string_literal: true

require "varar"
require "json"
require "tmpdir"
require_relative "support/kernel_command"

module DoctorWalk
  DAMAGES = {
    "clear the Codex AGENTS.md" => ->(kernel, _project) { File.write(File.join(kernel.home, ".codex", "AGENTS.md"), "") },
    "remove the Codex record" => ->(kernel, _project) { File.delete(File.join(kernel.home, ".agents", "plastic", "VERSION")) },
    "none" => ->(_kernel, _project) {},
    "remove references.db from the store" => ->(kernel, _project) { File.delete(store_file(kernel, "references.db")) },
    "drop the intents table from work_graph.db" => ->(kernel, _project) { drop(store_file(kernel, "work_graph.db"), "intents") },
    "remove the machine database" => ->(kernel, _project) { File.delete(*Dir.glob(File.join(kernel.plastic_home, "*.db"))) },
    "make the launcher not executable" => ->(kernel, _project) { File.chmod(0o644, File.join(kernel.plastic_home, "bin", "plastic")) },
    "clear the Plastic block from CLAUDE.md" => ->(kernel, _project) { File.write(File.join(kernel.home, ".claude", "CLAUDE.md"), "") },
    "clear the project CLAUDE.md" => ->(_kernel, project) { File.write(File.join(project, "CLAUDE.md"), "") }
  }.freeze

  module_function

  def call(row)
    Dir.mktmpdir("varar-doctor") do |home|
      kernel = KernelCommand.new(home)
      harness = row.fetch("harness", "claude-code")
      project = whole(kernel, harness)
      DAMAGES.fetch(row["damage"]).call(kernel, project)
      row.merge(walk(kernel, project, harness))
    end
  end

  def walk(kernel, project, harness)
    found = kernel.run("doctor", "--harness", harness, "--json")
    result = JSON.parse(found.out).fetch("result")
    repair = Array(result["repair"]).first
    run_repair(kernel, repair)
    { "exit" => found.code.to_s, "check" => finding(result), "repair" => shown(repair, project), "after repair" => kernel.run("doctor", "--harness", harness).code.to_s }
  end

  def shown(repair, project) = repair ? repair.sub(project, "PROJECT") : "none"

  def whole(kernel, harness)
    project = FileUtils.mkdir_p(File.join(kernel.home, "alpha")).first
    FileUtils.mkdir_p(File.join(kernel.home, (harness == "codex") ? ".codex" : ".claude"))
    kernel.run!("init", kernel.run("init").out[/(\d+)  \[.\] #{harness}$/, 1])
    kernel.run!("next")
    kernel.run!("project", "new", "alpha", project)
    File.write(File.join(project, "AGENTS.md"), "# Alpha\n\nPlastic's instructions are in ~/.plastic/PLASTIC.md.\n")
    File.write(File.join(project, "CLAUDE.md"), "@AGENTS.md\n")
    project
  end

  def store_file(kernel, name) = File.join(kernel.plastic_home, "stores", "alpha", name)

  def drop(path, table)
    connection = SQLite3::Database.new(path)
    connection.execute("DROP TABLE #{table}")
  ensure
    connection&.close
  end

  def finding(result)
    label, = result.find { |key, value| !%w[repair hook\ trust].include?(key) && value.is_a?(String) && !value.start_with?("ok") }
    return "none" unless label

    label.end_with?(".db") ? "machine database" : label
  end

  def run_repair(kernel, repair)
    return unless repair

    edit = repair.delete_prefix("add the line @AGENTS.md to ")
    return File.write(edit, "@AGENTS.md\n", mode: "a") unless edit == repair

    kernel.run!(*repair.split.drop(1))
  end
end

steps do
  sensor("the harness, the damage, the exit code, the check, the repair and the exit code after repair") do |_state, row|
    DoctorWalk.call(row)
  end
end
