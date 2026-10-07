# frozen_string_literal: true

require "digest"

module Plastic
  module Graph
    class DisposableCopy
      # What the files under a copy looked like at one moment, and how two such moments differ.
      class Snapshot
        DATABASE = /\.db(?:-journal|-wal|-shm)?\z/

        def self.differences(before, now)
          [["would add", now.except(*before.keys)],
            ["would remove", before.except(*now.keys)],
            ["would change", before.select { |rel, print| now.key?(rel) && now.fetch(rel) != print }]]
            .flat_map { |verb, rels| [verb].product(rels.keys) }.sort_by(&:last)
        end

        def self.fingerprint(path)
          return unless File.file?(path) && !DATABASE.match?(path)

          [Digest::SHA256.file(path).hexdigest, File.mtime(path)]
        end

        def self.of(root)
          Dir.glob("**/*", File::FNM_DOTMATCH, base: root).to_h { |rel| [rel, fingerprint(File.join(root, rel))] }.compact
        end
      end
    end
  end
end
