# frozen_string_literal: true

require "sqlite3"
require "tmpdir"
require "fileutils"

# A throwaway home whose store alpha is a beta.2 store: the three database files of that release, built from the SQL files in test/fixtures/stores/beta_2, every file unstamped.
module Beta2Store
  FOLDER = File.expand_path("../fixtures/stores/beta_2", __dir__)
  FILES = { "work_graph.db" => "work", "knowledge_graph.db" => "knowledge", "references.db" => "references" }.freeze

  def beta_2_home(references: true, rows: true, older: false)
    home = File.join(Dir.mktmpdir, ".plastic")
    root = File.join(home, "stores", "alpha")
    FileUtils.mkdir_p(root)
    File.write(File.join(home, "projects.yml"), "projects:\n  alpha:\n    path: #{Dir.mktmpdir}\n")
    origin = Plastic::Graph::Origin.new(home).id
    FILES.each { |file, name| build_beta_2_file(File.join(root, file), name, origin, rows) unless name == "references" && !references }
    drop_reason(File.join(root, "work_graph.db")) if older
    home
  end

  def build_beta_2_file(path, name, origin, rows)
    database = SQLite3::Database.new(path)
    database.execute_batch(File.read(File.join(FOLDER, "#{name}_layout.sql")))
    database.execute_batch(File.read(File.join(FOLDER, "#{name}_rows.sql")).gsub("ORIGIN", origin)) if rows
    database.close
  end

  def drop_reason(path)
    database = SQLite3::Database.new(path)
    database.execute('ALTER TABLE "intents" DROP COLUMN "reason"')
    database.close
  end

  def store_root(home) = File.join(home, "stores", "alpha")

  def store_path(home, name) = File.join(store_root(home), name)

  def beta_2_files(home) = Dir.glob(File.join(store_root(home), "**", "*")).select { |path| File.file?(path) }.to_h { |path| [path, File.binread(path)] }

  def read_file(path, sql, readonly: true)
    database = SQLite3::Database.new(path, readonly:)
    database.execute(sql)
  ensure
    database&.close
  end

  def stamp_of(path) = read_file(path, "PRAGMA user_version").flatten.first

  def columns_by_table(path)
    tables = read_file(path, "SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%' ORDER BY name").flatten
    tables.to_h { |table| [table, read_file(path, "SELECT cid, name, type, \"notnull\", dflt_value, pk FROM pragma_table_info('#{table}')")] }
  end

  def layouts_of(root) = %w[work_graph.db knowledge_graph.db retrieval_graph.db].select { |file| File.exist?(File.join(root, file)) }.to_h { |file| [file, columns_by_table(File.join(root, file))] }
end
