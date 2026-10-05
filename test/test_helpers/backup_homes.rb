# frozen_string_literal: true

require "tmpdir"
require "fileutils"

# A throwaway home with two registered projects, alpha and beta, each with
# its three store databases, and the calls that write and read backups of
# them. A fresh home is a plain folder, not the test's own transaction, so
# VACUUM INTO can run in it.
module BackupHomes
  def fresh_home
    home = File.join(Dir.mktmpdir, ".plastic")
    FileUtils.mkdir_p(home)
    File.write(File.join(home, "projects.yml"), "projects:\n  alpha:\n    path: #{Dir.mktmpdir}\n  beta:\n    path: #{Dir.mktmpdir}\n")
    %w[alpha beta].each { |slug| seed_store(home, slug) }
    home
  end

  def seed_store(home, slug)
    graphs = Plastic::Graph.open(home:, store: slug)
    graphs.work.write_intent(title: slug.capitalize)
    graphs.databases.values_at(:knowledge, :work, :references).each { |database| database.rows("SELECT 1") }
  end

  def at(*parts) = Time.utc(*parts)

  def local_at(*parts) = Time.new(*parts)

  def stamp(time) = time.getutc.strftime("%Y%m%d%H%M%S")

  def env_for(home) = { "PLASTIC_HOME" => home }

  def backup_at(home, time, slug: "alpha", databases: nil)
    home_db = Plastic::Graph.open(home:, store: slug).databases.fetch(:home)
    target = Plastic::Graph::Knowledge::Backup::Target.new(home_db, File.join(home, "stores", slug), slug, nil)
    Plastic::Graph::Knowledge::Backup::Publisher.new(target, now: time, databases:).call
  end

  def backups_dir(home, slug = "alpha") = File.join(home, "stores", slug, "backups")

  def folder_names(home, slug = "alpha")
    Dir.exist?(backups_dir(home, slug)) ? Dir.children(backups_dir(home, slug)).sort : []
  end

  def row_names(home, slug = "alpha")
    Plastic::Graph.open(home:, store: slug).retrieval.backups.map(&:name)
  end

  def store_file(home, name, slug = "alpha") = File.join(home, "stores", slug, "#{name}.db")

  def intent_count(home, slug = "alpha")
    Plastic::Graph.open(home:, store: slug).databases.fetch(:work).row("SELECT count(*) AS n FROM intents").fetch("n")
  end

  def add_intent(home, slug = "alpha") = Plastic::Graph.open(home:, store: slug).work.write_intent(title: "More")

  def backup_call(home, *argv) = plastic("backup", *argv, env: env_for(home), table: Plastic::CLI::TABLE)

  def list_call(home, *argv) = plastic("backup", "list", *argv, env: env_for(home), table: Plastic::CLI::TABLE)

  def purge_call(home, *argv) = plastic("backup", "purge", *argv, env: env_for(home), table: Plastic::CLI::TABLE)

  def restore_call(home, *argv) = plastic("backup", "restore", *argv, env: env_for(home), table: Plastic::CLI::TABLE)

  def assert_refused_with_usage(result, mention)
    assert_equal 2, result.code
    assert_equal "", result.out
    assert_includes result.err, mention
  end
end
