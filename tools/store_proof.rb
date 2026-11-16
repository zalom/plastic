# frozen_string_literal: true

require "digest"
require "fileutils"
require "optparse"
require "sqlite3"

# Runs a command against copies of the real stores and proves the real files
# stayed as they were. The copies and the four variables the command sees
# all sit under one job tmp folder, and the proof aborts before any copy when
# one of them does not. The four real databases are read only, copied with
# VACUUM INTO and checked with the quick check; afterwards each still holds
# user_version 0 and the VERSION record is the same.
module StoreProof
  # A path the command would see sits outside the job tmp.
  class Outside < StandardError; end

  # A real file or a copy cannot be trusted, or the real home changed.
  class Failed < StandardError; end

  # Ten phrases fixed for every proof run, so the hits of a search on the
  # copies can be compared run to run.
  PHRASES = [
    "work graph", "knowledge graph", "retrieval", "intent", "node", "edge",
    "savepoint", "backup", "migration", "traversal"
  ].freeze

  # The variables the command sees, each a folder under the job tmp.
  class Environment
    NAMES = { "HOME" => "home", "PLASTIC_HOME" => "plastic_home", "PLASTIC_SHARE" => "share", "PLASTIC_BIN" => "bin" }.freeze

    def initialize(job_tmp, plastic_home: nil)
      @job_tmp = job_tmp
      @plastic_home = plastic_home
    end

    def to_h
      paths = NAMES.transform_values { |folder| File.join(@job_tmp, folder) }
      @plastic_home ? paths.merge("PLASTIC_HOME" => @plastic_home) : paths
    end
  end

  # Refuses a variable whose path is not under the job tmp, dots resolved.
  class Guard
    def initialize(job_tmp)
      @job_tmp = File.expand_path(job_tmp)
    end

    def check(env)
      outside = env.reject { |_name, path| under?(path) }
      raise Outside, "#{outside.keys.sort.join(", ")} sit outside the job tmp #{@job_tmp}" unless outside.empty?
    end

    private

    def under?(path) = File.expand_path(path).start_with?(@job_tmp + File::SEPARATOR)
  end

  # The four real databases and the version record of one real home.
  class Real
    VERSION_FILE = "VERSION"

    def initialize(home, store)
      @home = home
      @files = ["local.db", *%w[work_graph knowledge_graph references].map { |name| File.join("stores", store, "#{name}.db") }]
    end

    attr_reader :files

    def path(file) = File.join(@home, file)

    def version_digest = Digest::SHA256.file(path(VERSION_FILE)).hexdigest

    def versions = @files.to_h { |file| [file, user_version(file)] }

    def problems(digest)
      stale = versions.reject { |_file, version| version.zero? }.map { |file, version| "#{file} has user_version #{version}" }
      stale << "#{VERSION_FILE} changed" unless version_digest == digest
      stale
    end

    def self.scalar(path, sql, readonly: false)
      db = SQLite3::Database.new(path, readonly: readonly)
      db.get_first_value(sql)
    rescue SQLite3::Exception => error
      raise Failed, "#{File.basename(path)}: #{error.message}"
    ensure
      db&.close
    end

    private

    def user_version(file)
      self.class.scalar(path(file), "PRAGMA user_version", readonly: true)
    end
  end

  # Copies each real database with VACUUM INTO and checks the copy.
  class Copies
    def initialize(real, plastic_home)
      @real = real
      @plastic_home = plastic_home
    end

    def call = @real.files.each { |file| copy(file) }

    private

    def copy(file)
      target = File.join(@plastic_home, file)
      FileUtils.mkdir_p(File.dirname(target))
      vacuum(file, target)
      verdict = Real.scalar(target, "PRAGMA quick_check")
      raise Failed, "#{file}: the copy fails the quick check (#{verdict})" unless verdict == "ok"
    end

    def vacuum(file, target)
      SQLite3::Database.new(@real.path(file), readonly: true) { |db| db.execute("VACUUM INTO ?", [target]) }
    rescue SQLite3::Exception => error
      raise Failed, "#{file}: #{error.message}"
    end
  end

  # The command line: `store-proof --job-tmp DIR [--real-home DIR] [--store SLUG] -- COMMAND...`.
  # Exit 0 when the command ran and the real files stayed, 1 when a file cannot be trusted or
  # changed or the command failed, 2 when called wrongly, 3 when a path sits outside the job tmp.
  class CLI
    def initialize(argv, out: $stdout, err: $stderr, runner: Runner)
      @argv = argv.dup
      @out = out
      @err = err
      @runner = runner
    end

    def call
      options = parse
      return usage("give --job-tmp DIR") unless options[:job_tmp]

      prove(options)
    rescue OptionParser::ParseError => error
      usage(error.message)
    rescue Outside => error
      refuse(error.message)
    rescue Failed => error
      fail_with(error.message)
    end

    # Starts the command with only the variables of the proof and the PATH.
    Runner = lambda do |env, command|
      system(env.merge("PATH" => ENV.fetch("PATH", "")), *command, unsetenv_others: true)
    end

    private

    def parse
      options = { real_home: File.join(Dir.home, ".plastic"), store: "plastic" }
      parser(options).order!(@argv)
      @argv.shift if @argv.first == "--"
      options
    end

    def parser(options)
      OptionParser.new do |parser|
        %i[job_tmp real_home store plastic_home].each do |key|
          parser.on("--#{key.to_s.tr("_", "-")} VALUE") { |value| options[key] = value }
        end
      end
    end

    def prove(options)
      env = Environment.new(options[:job_tmp], plastic_home: options[:plastic_home]).to_h
      Guard.new(options[:job_tmp]).check(env)
      real = Real.new(options[:real_home], options[:store])
      digest = real.version_digest
      copy_when_trusted(real, digest, env.fetch("PLASTIC_HOME"))
      finish(real, digest, @runner.call(env, @argv))
    end

    def copy_when_trusted(real, digest, plastic_home)
      stale = real.problems(digest)
      raise Failed, stale.join("; ") unless stale.empty?

      Copies.new(real, plastic_home).call
    end

    def finish(real, digest, ran)
      problems = real.problems(digest)
      problems << "the command failed" unless ran
      raise Failed, problems.join("; ") unless problems.empty?

      @out.puts "store proof: the command ran on copies and the real files kept user_version 0 and VERSION"
      0
    end

    def usage(message) = report(message, 2)

    def refuse(message) = report(message, 3)

    def fail_with(message) = report(message, 1)

    def report(message, code)
      @err.puts "store-proof: #{message}"
      code
    end
  end
end
