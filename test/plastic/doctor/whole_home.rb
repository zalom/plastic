# frozen_string_literal: true

require "json"
require "yaml"
require_relative "../../test_helper"
require_relative "../../../scripts/lib/compact_instructions"
require_relative "../../../scripts/lib/plastic/hooks/entries"

module WholeHome
  RUNNING = "9.1.0"
  SLUG = "alpha"

  def setup
    super
    @home = File.realpath(Dir.mktmpdir("plastic-doctor"))
    @plastic_home = File.join(@home, ".plastic")
    FileUtils.mkdir_p(File.join(@plastic_home, "stores", "global"))
  end

  def teardown
    Plastic::Graph::Database::ConnectionPool.release(@home)
    FileUtils.rm_rf(@home)
    super
  end

  def scope(env = {}) = scoped_harness(env:).scope

  def claude_dir = File.join(@home, ".claude")

  def project_dir = File.join(@home, "projects", SLUG)

  def store_dir = File.join(@plastic_home, "stores", SLUG)

  def hook_file = File.join(claude_dir, "hooks", "plastic-resume")

  def settings_path = File.join(claude_dir, "settings.json")

  def schema = Plastic::Graph::Schema

  def machine_key = (schema.databases.keys - schema.store).first

  def machine_path = File.join(@plastic_home, schema.file(machine_key))

  def store_path(key) = File.join(store_dir, schema.file(key))

  def whole_home
    write(File.join(@plastic_home, "VERSION"), "#{RUNNING}\n")
    write(File.join(@plastic_home, "PLASTIC.md"), "# Plastic\n")
    write(File.join(claude_dir, "plastic", "VERSION"), "#{RUNNING}\n")
    write(File.join(claude_dir, "CLAUDE.md"), CompactInstructions::BODY)
    whole_hooks
    whole_databases
    whole_project
  end

  def whole_hooks
    write(hook_file, "#!/bin/sh\n")
    File.chmod(0o755, hook_file)
    write_hooks(Plastic::Harnesses::EVENTS.keys.to_h { |event| [event, "\"#{hook_file}\" || true"] })
  end

  def write_hooks(commands)
    hooks = commands.transform_values { |command| [{ "matcher" => "", "hooks" => [{ "type" => "command", "command" => command }] }] }
    write(settings_path, JSON.generate("hooks" => hooks))
  end

  def whole_databases
    database(machine_path, machine_key)
    [SLUG, "global"].each { |store| Plastic::Graph.create(home: @plastic_home, store:) }
  end

  def database(path, key)
    FileUtils.mkdir_p(File.dirname(path))
    connection = SQLite3::Database.new(path)
    schema.prepare(connection, schema.fetch(key))
  ensure
    connection&.close
  end

  def whole_project
    write(File.join(@plastic_home, "projects.yml"), YAML.dump("projects" => { SLUG => { "path" => project_dir } }))
    write(File.join(project_dir, "AGENTS.md"), "# Alpha\n\nPlastic's instructions are in ~/.plastic/PLASTIC.md.\n")
    write(File.join(project_dir, "CLAUDE.md"), "# Alpha\n\n@AGENTS.md\n")
  end

  def forget_backfill(store)
    connection = SQLite3::Database.new(File.join(@plastic_home, "stores", store, schema.file(:knowledge)))
    connection.execute("DELETE FROM retrieval_backfills")
  ensure
    connection&.close
  end

  def drop_table(path, table)
    connection = SQLite3::Database.new(path)
    connection.execute("DROP TABLE #{table}")
  ensure
    connection&.close
  end

  def write(path, text)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, text)
  end
end
