# frozen_string_literal: true

require "sqlite3"

# Gives a throwaway home the settings a config.yml text holds, the way the
# migration does: the rows in plastic.db, then the file printed from them.
module ConfigHomes
  def seed_config(home, text)
    path = File.join(home, "config.yml")
    FileUtils.mkdir_p(home)
    File.write(path, text)
    local = Plastic::Graph::Database.open_local(home).fetch(:local)
    local.rows("SELECT 1")
    SQLite3::Database.new(local.path) { |db| Plastic::Config::Import.new(path).call(db) }
    Plastic::Config::Store.new(home).print
  end

  def setting_rows(home)
    SQLite3::Database.new(File.join(home, "plastic.db"), readonly: true) { |db| db.execute("SELECT scope, key, value FROM settings ORDER BY scope, key") }
  end
end
