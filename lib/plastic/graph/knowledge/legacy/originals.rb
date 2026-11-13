# frozen_string_literal: true

require "digest"

module Plastic
  module Graph
    module Knowledge
      module Legacy
        # Keeps original bytes when an import rewrites a legacy file.
        class Originals
          INTENT = %r{\Astore/(.*?)(?:--|/)}

          def initialize(databases, counts)
            @databases = databases
            @counts = counts
          end

          def keep_changed_originals(folder, originals)
            originals.each { |path, before| keep_original(path, before, path[INTENT, 1]) unless folder.holds?(path, before) }
          end

          def keep_original(path, bytes, intent_id)
            row = { name: "originals/#{path}", mode: 0o644, mtime: Time.now.to_i, sz: bytes.bytesize,
                    data: SQLite3::Blob.new(bytes), intent_id:, sha256: Digest::SHA256.hexdigest(bytes) }
            @databases.fetch(:references).transaction { |batch| batch.put(:sqlar, row, statement: :upsert) }
            @counts[:kept] += 1
          end

          def keep_roadmap_original(root, slug, original_bytes)
            canonical = File.join(root, "roadmaps", "#{slug}.md")
            after = File.exist?(canonical) ? File.binread(canonical) : nil
            keep_original("roadmaps/#{slug}.md", original_bytes, nil) unless after == original_bytes
          end
        end
      end
    end
  end
end
