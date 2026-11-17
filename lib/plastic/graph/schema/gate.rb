# frozen_string_literal: true

require_relative "../behind"
require_relative "sequences"

module Plastic
  module Graph
    # The check a database passes on its first use in a process. A new, empty
    # file gets the declared schema and the newest stamp. A file at the newest
    # version passes. A file behind its sequence is refused after one wait
    # for the write lock, because another session may be migrating it; a
    # file ahead of this code is refused too. Nothing here migrates an old
    # file: the install and the update do, through SchemaRunner.
    class SchemaGate
      VERSION = "PRAGMA user_version"

      def initialize(connection, sequence:, key:, file:)
        @connection = connection
        @sequence = sequence
        @key = key
        @file = file
      end

      def call
        version = stamped
        return if version == newest

        raise Ahead, refusal("is newer than this code (version #{version}, code #{newest})") if version > newest

        settle(version)
      rescue SQLite3::BusyException
        raise Behind, refusal("is busy and behind this code (version #{version}, code #{newest})")
      end

      private

      def newest = SchemaSequences.newest(@sequence)

      def stamped = @connection.get_first_value(VERSION).to_i

      def empty? = @connection.get_first_value("SELECT COUNT(*) FROM sqlite_master WHERE name NOT LIKE 'sqlite_%'").zero?

      def settle(version)
        return if empty? && build_layout

        verify_current(version)
      end

      # Builds the declared schema and stamps it in one transaction under the write lock. A second session
      # that waited for the lock finds the tables there and builds nothing.
      def build_layout
        under_write_lock do
          next false unless empty?

          SchemaSequences::CURRENT_LAYOUT.call(@connection, @key)
          @connection.execute("#{VERSION} = #{newest}")
          true
        end
      end

      def verify_current(version)
        current = under_write_lock { stamped }
        raise Behind, refusal("is behind this code (version #{version}, code #{newest})") unless current == newest
      end

      # A call already inside a transaction holds the write lock or will; a call outside one takes it here.
      def under_write_lock(&)
        return yield if @connection.transaction_active?

        @connection.transaction(:immediate, &)
      end

      def refusal(reason) = "#{@file} #{reason}; run plastic update"
    end
  end
end
