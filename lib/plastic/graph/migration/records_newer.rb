# frozen_string_literal: true

require_relative "../schema"
require_relative "../schema/state"

module Plastic
  module Graph
    # The answer of a migration for a database that records versions this code does not know: it was written by newer
    # code, so the run leaves it as it is and names the versions. Reading it opens the file read only.
    RecordsNewer = Data.define(:versions) do
      # The answer for the file at `path`, or nil when the file is missing or its versions are all known.
      def self.read(path, kind)
        return unless File.file?(path)

        reading = SchemaState.of_file(path, kind)
        new(reading.unknown) if reading.ahead?
      end

      # Each database of the home that records unknown versions, by store slug or "home", read only.
      def self.in_home(home)
        found = Dir.glob(File.join(home, "stores", "*", Schema.file(:knowledge))).to_h { |file| [File.basename(File.dirname(file)), read(file, :store)] }
        found["home"] = read(File.join(home, "plastic.db"), :home)
        found.compact.transform_values(&:versions)
      end

      # The words that name such databases and their versions.
      def self.describe(newer) = newer.map { |name, versions| "#{name} records #{versions.join(", ")}" }.join("; ")
    end
  end
end
