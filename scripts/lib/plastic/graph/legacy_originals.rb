# frozen_string_literal: true

require "digest"

module Plastic
  module Graph
    # Keeps original bytes when an import rewrites a legacy file.
    class LegacyOriginals
      def keep_changed_originals(databases, folder, originals, counts)
        originals.each do |path, before|
          after = folder.exist?(path) ? folder.read(path) : nil
          next if after == before

          intent_id = path.sub(%r{\Astore/}, "").split("/").first.split("--").first
          keep_original(databases, path, before, intent_id, counts)
        end
      end

      def keep_original(databases, path, bytes, intent_id, counts)
        row = { name: "originals/#{path}", mode: 0o644, mtime: Time.now.to_i, sz: bytes.bytesize,
                data: SQL::Bytes.new(bytes), intent_id:, sha256: Digest::SHA256.hexdigest(bytes) }
        databases.fetch(:references).transaction { |batch| batch.put(:sqlar, row, statement: :upsert) }
        counts[:kept] += 1
      end

      def keep_roadmap_original(databases, root, slug, original_bytes, counts)
        canonical = File.join(root, "roadmaps", "#{slug}.md")
        after = File.exist?(canonical) ? File.binread(canonical) : nil
        return if after == original_bytes

        keep_original(databases, "roadmaps/#{slug}.md", original_bytes, nil, counts)
      end
    end
  end
end
