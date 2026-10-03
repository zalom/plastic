# frozen_string_literal: true

require "digest"
require_relative "record"

module Plastic
  module Graph
    # One archive this machine wrote: home.db and every store's three
    # databases, packed into one gzipped tar under backups/.
    Backup = Data.define(:name, :files, :bytes, :sha256, :at, :session_id) do
      include Record

      def flag(home_dir)
        path = File.join(home_dir, "backups", name)
        return "missing" unless File.exist?(path)

        (Digest::SHA256.file(path).hexdigest == sha256) ? nil : "changed"
      end
    end
  end
end
