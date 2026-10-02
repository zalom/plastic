# frozen_string_literal: true

require_relative "record"

module Plastic
  module Graph
    # One archive this machine wrote: home.db and every store's three
    # databases, packed into one gzipped tar under backups/.
    Backup = Data.define(:name, :files, :bytes, :sha256, :at, :session_id) do
      include Record
    end
  end
end
