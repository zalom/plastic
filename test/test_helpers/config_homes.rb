# frozen_string_literal: true

module ConfigHomes
  def seed_config(home, text)
    path = File.join(home, "config.yml")
    FileUtils.mkdir_p(home)
    File.write(path, text)
    Plastic::Config::Upgrade.new(path).call
    local = Plastic::Graph::Database.open_local(home).fetch(:local)
    local.migrate
    local.transaction { |batch| batch.add('DELETE FROM "settings"') }
    Plastic::Wiring.store(home).print_current
  end

  def setting_rows(home) = Plastic::Graph::Database.open_local(home).fetch(:local).rows("SELECT scope, key, value FROM settings ORDER BY scope, key").map(&:values)
end
