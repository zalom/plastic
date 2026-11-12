# frozen_string_literal: true

require "digest"
require_relative "../record"

module Plastic
  module Graph
    module Knowledge
      # One backup this machine wrote: a folder under the store's backups/,
      # named SLUG/TIMESTAMP, holding copies of the store databases.
      Backup = Data.define(:name, :files, :bytes, :sha256, :at, :session_id) do
        include Record

        # The store the backup belongs to, and its folder name.
        def store = name.split("/", 2).first

        def folder = name.split("/", 2).last

        def flag(home_dir)
          folders = Backup::Folders.new(File.join(home_dir, "stores", store))
          return "missing" unless folders.exist?(folder)

          (folders.digest(folder) == sha256) ? nil : "changed"
        end
      end
    end
  end
end

require_relative "backup/folders"
