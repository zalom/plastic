# frozen_string_literal: true

require "digest"
require "fileutils"
require "optparse"
require "sqlite3"

# Runs a command against copies of the real stores and proves the real files
# stayed as they were. The copies and the four variables the command sees
# all sit under one job tmp folder, and the proof aborts before any copy when
# one of them does not. The real databases are read only, copied with
# VACUUM INTO and checked with the quick check; afterwards each still holds
# user_version 0 and the VERSION record is the same. Every store under
# stores/ is taken; a database a store lacks is skipped by name. The other
# files of the home are copied with cp.
module StoreProof
  # A path the command would see sits outside the job tmp.
  class Outside < StandardError; end

  # A real file or a copy cannot be trusted, or the real home changed.
  class Failed < StandardError; end

  # The reasons a proof cannot be trusted; none means it can.
  Problems = Data.define(:found) do
    def self.after(found, ran) = new([*found, *("the command failed" if [nil, false].include?(ran))])

    def check = (raise Failed, found.join("; ") if found.any?)
  end

  # Ten phrases fixed for every proof run, so the hits of a search on the
  # copies can be compared run to run.
  PHRASES = [
    "work graph", "knowledge graph", "retrieval", "intent", "node", "edge",
    "savepoint", "backup", "migration", "traversal"
  ].freeze

  # Counts the notes of a copied home that hold each phrase; a phrase with no hit proves nothing.
  class Hits
    def initialize(home, phrases = PHRASES)
      @phrases = phrases
      @notes = Dir.glob(File.join(home, "**", "*.md")).map { |file| File.read(file).downcase }
    end

    def counts = @phrases.to_h { |phrase| [phrase, holding(phrase)] }

    private

    def holding(phrase) = @notes.count { |note| note.include?(phrase) }
  end

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

  # The real databases and the version record of one real home: the home
  # database and every database of every store under stores/.
  class Real
    VERSION_FILE = "VERSION"
    STORE_DATABASES = %w[work_graph knowledge_graph retrieval_graph].freeze
    SIDE_FILE = /\.db(-wal|-shm|-journal)?\z/
    MACHINE = "plastic.db"
    MACHINE_BEFORE_UPDATE = "local.db"

    def initialize(home)
      @home = home
      @files = [machine, *Dir.glob(File.join(home, "stores", "*", "*.db")).map { |file| file.delete_prefix("#{home}/") }.sort]
    end

    attr_reader :files

    def path(file) = File.join(@home, file)

    def version_digest = Digest::SHA256.file(path(VERSION_FILE)).hexdigest

    def versions = @files.to_h { |file| [file, user_version(file)] }

    # The databases a store folder lacks, by their path in the home.
    def skipped
      Dir.glob(File.join(@home, "stores", "*")).sort.flat_map { |store| lacking(File.basename(store)) }
    end

    # The files of the home that are not databases, by their path in the home.
    def others = Dir.glob(File.join(@home, "**", "*"), File::FNM_DOTMATCH).select { |file| File.file?(file) && !file.match?(SIDE_FILE) }.map { |file| file.delete_prefix("#{@home}/") }.sort

    def problems(digest)
      stale = versions.reject { |_file, version| version.zero? }.map { |file, version| "#{file} has user_version #{version}" }
      changed?(digest) ? [*stale, "#{VERSION_FILE} changed"] : stale
    end

    def changed?(digest) = version_digest != digest

    def self.scalar(path, sql)
      SQLite3::Database.open(path, readonly: true) { |db| db.get_first_value(sql) }
    rescue SQLite3::Exception => error
      raise Failed, "#{File.basename(path)}: #{error.message}"
    end

    private

    def lacking(store) = STORE_DATABASES.map { |name| File.join("stores", store, "#{name}.db") }.reject { |file| File.exist?(path(file)) }

    # The machine database of a home that has not run the update yet is still local.db.
    def machine
      return MACHINE if File.exist?(path(MACHINE))

      File.exist?(path(MACHINE_BEFORE_UPDATE)) ? MACHINE_BEFORE_UPDATE : MACHINE
    end

    def user_version(file)
      self.class.scalar(path(file), "PRAGMA user_version")
    end
  end

  # Copies each real database with VACUUM INTO and checks the copy.
  class Copies
    def initialize(real, plastic_home)
      @real = real
      @plastic_home = plastic_home
    end

    def call
      @real.files.each { |file| copy(file) }
      @real.others.each { |file| copy_plain(file) }
    end

    private

    def copy_plain(file)
      target = File.join(@plastic_home, file)
      FileUtils.mkdir_p(File.dirname(target))
      FileUtils.cp(@real.path(file), target)
    end

    def copy(file)
      target = File.join(@plastic_home, file)
      FileUtils.mkdir_p(File.dirname(target))
      vacuum(file, target)
      verdict = Real.scalar(target, "PRAGMA quick_check")
      (verdict == "ok") || raise(Failed, "#{file}: the copy fails the quick check (#{verdict})")
    end

    def vacuum(file, target)
      SQLite3::Database.new(@real.path(file), readonly: true) { |db| db.execute("VACUUM INTO ?", [target]) }
    rescue SQLite3::Exception => error
      raise Failed, "#{file}: #{error.message}"
    end
  end

  # The switches of the command line, read before the command.
  module Options
    KEYS = %i[job_tmp real_home plastic_home].freeze

    def self.read(argv)
      values = { real_home: File.join(Dir.home, ".plastic") }
      KEYS.each_with_object(OptionParser.new) { |key, parser| add(parser, values, key) }.order!(argv)
      values
    end

    def self.add(parser, values, key) = parser.on("--#{key.to_s.tr("_", "-")} VALUE") { |value| values[key] = value }
  end

  # The command line: `store-proof --job-tmp DIR [--real-home DIR] -- COMMAND...`.
  # Exit 0 when the command ran and the real files stayed, 1 when a file cannot be trusted or
  # changed or the command failed, 2 when called wrongly, 3 when a path sits outside the job tmp.
  class CLI
    CODES = { OptionParser::ParseError => 2, Outside => 3, Failed => 1 }.freeze

    def initialize(argv, out: $stdout, err: $stderr, runner: Runner.new)
      @argv = argv.dup
      @out = out
      @err = err
      @runner = runner
    end

    def call
      options = parse
      return usage("give --job-tmp DIR") unless options[:job_tmp]

      prove(options)
    rescue OptionParser::ParseError, Outside, Failed => error
      report(error.message, CODES.find { |kind, _code| error.is_a?(kind) }.last)
    end

    # Starts the command with only the variables of the proof and the PATH.
    # The spawner is passed in, so a test never starts a process.
    class Runner
      def initialize(spawner: Kernel.method(:system), path: ENV.fetch("PATH", ""))
        @spawner = spawner
        @path = path
      end

      def call(env, command) = @spawner.call(env.merge("PATH" => @path), *command, unsetenv_others: true)
    end

    private

    def parse = Options.read(@argv)

    def prove(options)
      job_tmp = options[:job_tmp]
      env = Environment.new(job_tmp, plastic_home: options[:plastic_home]).to_h
      Guard.new(job_tmp).check(env)
      real = Real.new(options[:real_home])
      digest = real.version_digest
      copy_when_trusted(real, digest, env.fetch("PLASTIC_HOME"))
      finish(real, digest, @runner.call(env, @argv))
    end

    def copy_when_trusted(real, digest, plastic_home)
      Problems.new(real.problems(digest)).check
      Copies.new(real, plastic_home).call
      real.skipped.each { |file| @out.puts "skipped #{file}: missing" }
      report_hits(plastic_home)
    end

    def report_hits(plastic_home)
      counts = Hits.new(plastic_home).counts
      counts.each { |phrase, count| @out.puts "hits: #{phrase} #{count}" }
      empty = counts.select { |_phrase, count| count.zero? }.keys
      raise Failed, "no hit for #{empty.join(", ")}" unless empty.empty?
    end

    def finish(real, digest, ran)
      Problems.after(real.problems(digest), ran).check
      @out.puts "store proof: the command ran on copies and the real files kept user_version 0 and VERSION"
      0
    end

    def usage(message) = report(message, 2)

    def report(message, code)
      @err.puts "store-proof: #{message}"
      code
    end
  end
end
