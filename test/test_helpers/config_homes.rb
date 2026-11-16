# frozen_string_literal: true

module ConfigHomes
  ROW = 'INSERT OR REPLACE INTO "settings"("scope", "key", "value") VALUES (:scope, :key, :value)'

  def seed_config(home, text)
    path = File.join(home, "config.yml")
    FileUtils.mkdir_p(home)
    File.write(path, text)
    Plastic::Config::Upgrade.new(path).call
    local = Plastic::Graph::Database.open_local(home).fetch(:local)
    local.migrate(Plastic::Graph::SchemaSequences::SEQUENCES)
    local.transaction { |batch| Plastic::Graph::SchemaHome3.rows(path).each { |scope, key, value| batch.add(ROW, scope:, key:, value:) } }
    Plastic::Config::Store.new(home).print
  end

  def setting_rows(home) = Plastic::Graph::Database.open_local(home).fetch(:local).rows("SELECT scope, key, value FROM settings ORDER BY scope, key").map(&:values)
end
