# frozen_string_literal: true

require "fileutils"
require "json"
require "open3"
require "rbconfig"
require "tmpdir"

# Runs the kernel command line of scripts/lib/plastic in a child process,
# against a disposable home. The kernel defines the same constants as the
# live command line, so it never loads into the process that runs Varar.
# The rows are read back through the sqlite3 program, as a person would.
class KernelCommand
  KERNEL = File.expand_path("../../../scripts/lib/plastic", __dir__)
  LEGACY_STORE = File.expand_path("../../plastic/fixtures/legacy_store", __dir__)
  PROGRAM = "require ARGV.shift; exit Plastic::CLI.call(ARGV)"

  # One call: its exit code, what it printed and what it said went wrong.
  Call = Data.define(:code, :out, :err) do
    # The lines that tell what the call did: neither the database report nor next: and because:.
    def said = out.lines(chomp: true).grep_v(/\A(?:wrote:|  |next:|because:|\z)/)

    # The reason a stopped call gives, without the prefix that names the workflow.
    def reason = err.lines.first.to_s.chomp.sub(/\Aplastic: (?:refused, |code_\w+, [^:]+: (?:Plastic::Invalid: )?)?/, "")

    # What the call did, then why it stopped, in one cell.
    def result = [*said, *(reason unless code.zero?)].join(" / ").then { |text| text.empty? ? "none" : text }
  end

  attr_reader :home

  # A home copied from one built once per process under `name`, so a row
  # pays for its own call and not for the store every row starts from.
  def self.copied(home, name, &build)
    templates = (@templates ||= {})
    source = templates[name] ||= Dir.mktmpdir("varar-template").tap do |dir|
      build.call(new(dir))
      at_exit { FileUtils.remove_entry(dir) }
    end
    FileUtils.cp_r("#{source}/.", home)
    new(home)
  end

  def initialize(home)
    @home = home
    @env = { "HOME" => home, "PLASTIC_HOME" => plastic_home, "PLASTIC_TMP" => File.join(home, "tmp"),
             "CLAUDE_CODE_SESSION_ID" => nil, "RUBYOPT" => nil, "BUNDLER_SETUP" => nil }
  end

  def plastic_home = File.join(home, ".plastic")

  def store = File.join(plastic_home, "stores", "global")

  def path(rel) = File.join(store, rel)

  def origin = File.read(File.join(plastic_home, "origin_id")).strip

  def run(*args)
    out, err, status = Open3.capture3(@env, RbConfig.ruby, "-e", PROGRAM, KERNEL, *args, chdir: home)
    Call.new(status.exitstatus, out, err)
  end

  # Runs the call and raises unless it exits 0, for the steps that set a store up.
  def run!(*args)
    call = run(*args)
    raise "plastic #{args.join(" ")}: #{call.code}\n#{call.out}#{call.err}" unless call.code.zero?

    call
  end

  def read(rel) = File.read(path(rel))

  def write(rel, text)
    FileUtils.mkdir_p(File.dirname(path(rel)))
    File.write(path(rel), text)
  end

  # Intent 1, Alpha, with a spec.md read into its rows: the store the sync documents start from.
  def self.alpha(home)
    copied(home, :alpha) do |kernel|
      kernel.run!("intent", "new", "Alpha")
      kernel.write("store/1--alpha/spec.md", "# Spec\n")
      kernel.run!("sync", "up")
    end
  end

  def copy_legacy_store
    FileUtils.mkdir_p(File.dirname(store))
    FileUtils.cp_r(LEGACY_STORE, store)
  end

  # The rows one query returns from one database of the store, as arrays.
  def rows(database, sql)
    return [] unless File.exist?(path(database))

    out, err, status = Open3.capture3("sqlite3", "-json", path(database), sql)
    raise "sqlite3: #{err}" unless status.success?

    out.strip.empty? ? [] : JSON.parse(out).map(&:values)
  end

  # Every file under `dir` with its bytes.
  def snapshot(dir)
    base = path(dir)
    Dir.glob("**/*", File::FNM_DOTMATCH, base:).select { |rel| File.file?(File.join(base, rel)) }.sort
      .to_h { |rel| [rel, File.binread(File.join(base, rel))] }
  end
end
