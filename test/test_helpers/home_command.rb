# frozen_string_literal: true

require "fileutils"
require "sqlite3"
require "stringio"

# One disposable home that runs the command line in the test's own process. The tests of two homes
# build one for each machine. Its rows are read back through the sqlite3 gem, on their own connection.
class HomeCommand
  Call = Data.define(:code, :out, :err) do
    # The files the call printed, from the files: row.
    def files
      block = out.lines(chomp: true).drop_while { |line| !line.start_with?("files:") }.take_while { |line| !line.empty? }
      block.map { |line| line.delete_prefix("files:").strip }.join(" / ").then { |text| text.empty? ? "none" : text }
    end

    # The reason a stopped call gives, without the prefix that names the workflow.
    def reason = err.lines.first.to_s.chomp.sub(/\Aplastic: (?:refused, )?(?:Plastic::Invalid: )?/, "")
  end

  attr_reader :home

  def initialize(home)
    @home = home
    Plastic::Graph.create(home: plastic_home, store: "global") unless File.exist?(plastic_home)
  end

  def plastic_home = File.join(home, ".plastic")

  def store = File.join(plastic_home, "stores", "global")

  def path(rel) = File.join(store, rel)

  def origin = File.read(File.join(plastic_home, "origin_id")).strip

  def command(*args, input: "", env: {})
    out = StringIO.new
    err = StringIO.new
    code = Plastic::CLI.call(args, environment: environment(env, input, out, err), table: Plastic::CLI::TABLE)
    Call.new(code, out.string, err.string)
  end

  # Runs the call and raises unless it exits 0, for the steps that set a store up.
  def command!(*args, **options)
    call = command(*args, **options)
    raise "plastic #{args.join(" ")}: #{call.code}\n#{call.out}#{call.err}" unless call.code.zero?

    call
  end

  def read(rel) = File.read(path(rel))

  def write(rel, text)
    FileUtils.mkdir_p(File.dirname(path(rel)))
    File.write(path(rel), text)
  end

  # The rows one statement returns from one database of the store, as arrays.
  def rows(database, sql)
    return [] unless File.exist?(path(database))

    connection = SQLite3::Database.new(path(database))
    connection.execute(sql)
  ensure
    connection&.close
  end

  # Every file under `dir` with its bytes.
  def snapshot(dir)
    base = path(dir)
    Dir.glob("**/*", File::FNM_DOTMATCH, base:).select { |rel| File.file?(File.join(base, rel)) }.sort
      .to_h { |rel| [rel, File.binread(File.join(base, rel))] }
  end

  # Closes the connections the commands of this home left open.
  def release = Plastic::Graph::Database::ConnectionPool.release(home)

  private

  def environment(env, input, out, err)
    Plastic::CLI::Command::Environment.new(env: { "PLASTIC_HOME" => plastic_home, "PLASTIC_TMP" => File.join(home, "tmp") }.merge(env),
      input: StringIO.new(input), out:, err:, home:, directory: home)
  end
end
