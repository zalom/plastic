# frozen_string_literal: true

require "fileutils"
require "open3"

module Plastic
  module Graph
    # One SQLite file and the sqlite3 session that runs its scripts.
    class Database
      # The open sessions of this Ruby process, one per database file, as a
      # Rails process keeps one connection per database. A forked child
      # starts with none: the pipes it inherits belong to its parent.
      module ConnectionPool
        def self.for(path) = sessions[path] ||= Session.new(path)

        def self.remove(path) = sessions.delete(path)

        def self.disconnect = sessions.each_value(&:close).clear

        def self.sessions
          pid = Process.pid
          @sessions = {} unless @pid == pid
          @pid = pid
          @sessions
        end
      end

      # One sqlite3 process on one database file, open until a disconnect or
      # the end of this Ruby process. Each script goes in on its stdin and its
      # output comes back up to an end marker. Under -bail a failed statement
      # ends the process, so an open transaction rolls back, and the next call
      # opens a new session.
      class Session
        MARK = "plastic:end"

        # The three pipes of one sqlite3 process and the thread that waits on it.
        Pipes = Data.define(:input, :output, :errors, :process)

        # Writes to the process and ends it.
        class Pipes
          def write(text)
            input.write(text)
            input.flush
          rescue IOError, SystemCallError
            nil
          end

          def close
            input.close unless input.closed?
            process.join
            output.close
            errors.close
          end
        end

        def initialize(path)
          @path = path
          @pipes = Pipes.new(*Open3.popen3("sqlite3", "-json", "-bail", folder))
        end

        # The output of one script, or a raised Error when the process ended.
        def call(script)
          writer = Thread.new { write(script) }
          out = read
          writer.join
          out || failed
        end

        def close = @pipes.close

        private

        # The statement separator ends a script whose last statement has none.
        def write(script) = @pipes.write("#{script}\n;\n.print #{MARK}\n")

        # The lines before the end marker; nil when the process ended first.
        def read
          lines = +""
          while (line = @pipes.output.gets)
            return lines if line.chomp == MARK

            lines << line
          end
        end

        def failed
          ConnectionPool.remove(@path)
          message = @pipes.errors.read.strip
          close
          raise Error, "#{File.basename(@path)}: #{message}"
        end

        # The database's path, with its folder made first.
        def folder
          FileUtils.mkdir_p(File.dirname(@path))
          @path
        rescue SystemCallError => error
          raise Error, "#{File.basename(@path)}: #{error.message}"
        end
      end

      at_exit { ConnectionPool.disconnect }
    end
  end
end
