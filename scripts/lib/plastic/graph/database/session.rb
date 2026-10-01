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
      # the end of this Ruby process. Each script goes in on its input, and
      # its output and its errors come back in order up to an end marker. A
      # failed statement raises and rolls back any open transaction; the
      # session stays open, as a Rails connection survives an error.
      class Session
        MARK = "plastic:end"
        ERROR = /\A(?:Parse error|Runtime error|Error:)/
        DEADLINE = 30

        # The two pipes of one sqlite3 process and the thread that waits on it.
        Pipes = Data.define(:input, :output, :process)

        # Writes to the process and ends it.
        class Pipes
          def write(text)
            input.write(text)
            input.flush
          end

          def close
            input.close unless input.closed?
            process.join
            output.close
          end

          def kill
            Process.kill(:KILL, process.pid)
            close
          end
        end

        def initialize(path, deadline: DEADLINE)
          @path = path
          @deadline = deadline
          @pipes = Pipes.new(*Open3.popen2e("sqlite3", "-json", folder))
        end

        # The output of one script. A failed statement raises Error with
        # sqlite3's line after the open transaction rolls back.
        def call(script)
          lines = exchange(script)
          error = lines.find { |line| line.match?(ERROR) }
          error ? roll_back(error) : lines.join
        end

        def close = @pipes.close

        private

        def name = File.basename(@path)

        def roll_back(error)
          exchange("ROLLBACK;")
          raise Error, "#{name}: #{error.strip}"
        end

        # Sends one script and reads its lines; the separator ends a script
        # whose last statement has none.
        def exchange(script)
          writer = Thread.new do
            Thread.current.report_on_exception = false
            @pipes.write("#{script}\n;\n.print #{MARK}\n")
          end
          read(Process.clock_gettime(Process::CLOCK_MONOTONIC) + @deadline).tap { writer.join }
        end

        # The lines before the end marker, waiting at most until `deadline`.
        def read(deadline)
          lines = []
          while (line = next_line(deadline))
            return lines if line.chomp == MARK

            lines << line
          end
          ended
        end

        def next_line(deadline)
          left = deadline - Process.clock_gettime(Process::CLOCK_MONOTONIC)
          output = @pipes.output
          no_answer unless left.positive? && output.wait_readable(left)
          output.gets
        end

        def no_answer
          ConnectionPool.remove(@path)
          @pipes.kill
          raise Error, "#{name}: sqlite3 gave no answer in #{@deadline} s"
        end

        def ended
          ConnectionPool.remove(@path)
          close
          raise Error, "#{name}: sqlite3 ended before its answer"
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
