# frozen_string_literal: true

require_relative "../../schema"
require_relative "archive_name"

module Plastic
  module Graph
    module Knowledge
      class Backup
        # The databases a backup packs: home.db and each store's databases that exist on disk.
        module Sources
          def self.plan(home)
            { name: ArchiveName.for(home), files: of(home).count { |(_name, path)| File.file?(path) } }
          end

          def self.of(home)
            [["home.db", File.join(home, "home.db")]] + stores(home)
          end

          def self.stores(home)
            Dir.glob(File.join(home, "stores", "*")).select { |path| File.directory?(path) }.sort.flat_map { |store| entries(store) }
          end

          def self.entries(store)
            slug = File.basename(store)
            Schema.store.filter_map { |key| entry(store, slug, key) }
          end

          def self.entry(store, slug, key)
            file = Schema.file(key)
            db = File.join(store, file)
            ["stores/#{slug}/#{file}", db] if File.exist?(db)
          end
        end
      end
    end
  end
end
