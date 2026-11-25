# frozen_string_literal: true

module Plastic
  module Installations
    # One harness install: the folders it may touch, the files and Plastic
    # folders it made, its settings file with the hook entries, status line
    # and deny entries it added there, and the marked sections it wrote into
    # instruction files.
    Record = Data.define(:harness, :version, :roots, :files, :folders, :settings, :hooks, :status_line, :permissions,
      :sections) do
      def self.from_h(hash) = new(**members.to_h { |member| [member, hash[member.to_s]] })
    end
  end
end
