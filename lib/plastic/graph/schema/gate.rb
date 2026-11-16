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

        empty? ? begin_layout : wait_for_current(version)
      end

      private

      def newest = SchemaSequences.newest(@sequence)

      def stamped = @connection.get_first_value(VERSION).to_i

      def empty? = @connection.get_first_value("SELECT COUNT(*) FROM sqlite_master WHERE name NOT LIKE 'sqlite_%'").zero?

      def begin_layout
        SchemaSequences::CURRENT_LAYOUT.call(@connection, @key)
        @connection.execute("#{VERSION} = #{newest}")
      end

      def wait_for_current(version)
        @connection.execute("BEGIN IMMEDIATE")
        current = stamped
        @connection.execute("ROLLBACK")
        raise Behind, refusal("is behind this code (version #{version}, code #{newest})") unless current == newest
      rescue SQLite3::BusyException
        raise Behind, refusal("is busy and behind this code (version #{version}, code #{newest})")
      end

      def refusal(reason) = "#{@file} #{reason}; run plastic update"
    end
  end
end
