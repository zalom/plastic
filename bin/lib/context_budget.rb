# encoding: UTF-8
# frozen_string_literal: true

require "date"
require "fileutils"
require "json"
require "open3"
require "rbconfig"
require "tmpdir"
require "yaml"
require_relative "../../scripts/lib/store_layout"

# ContextBudget: the measurement behind Plastic's two context numbers. The core
# block stays under 8,192 bytes and the whole per-boot doctrine read under
# 15,000. Everything here is measured: the bench builds a fixture
# home by running the real installer into a temporary HOME, runs the real
# `scripts/hook-session-start` against it N times, and reports what a boot
# actually costs.
#
# Maintainer tool. It lives under bin/ beside bin/test, is never registered in
# installer_core.rb, and is never installed into ~/.plastic: it reads repo
# fixtures, so it has no meaning on an installed copy.
#
# Hermetic and DI throughout: every path is a keyword argument, the boot
# subprocess's environment is a pure function of the fixture, and the runner is
# injectable. Nothing reads the real ~/.plastic or ~/.claude, and nothing here
# touches the network.
module ContextBudget
  # The two ceilings plus the one ratchet.
  #
  #   core              PLASTIC.md, the always-on core block.
  #   boot              the additionalContext hook-session-start emits. The
  #                     whole-read ceiling, enforced on the only quantity that is
  #                     actually read on every boot and can be measured exactly.
  #   boot_plus_catalog boot injection plus the skill catalog the harness loads.
  #                     A ratchet over the measured 16,537, so
  #                     the second-largest per-boot cost cannot regrow unwatched.
  #                     Lower it as the catalog shrinks; never raise it.
  #   standing          every byte Plastic puts into a session before it does
  #                     any work: the core block, the boot injection, the skill
  #                     catalog and the agent catalog. Only what Plastic
  #                     introduces can be capped, never the whole context; the
  #                     cap is 5,000 bytes, about 1,250 tokens.
  CEILINGS = { core: 8_192, boot: 15_000, boot_plus_catalog: 17_500, standing: 5_000 }.freeze

  # The doctrine working set (boot + _decision-tables.md + the median skill body)
  # is reported against this target, never enforced: its median term steps by
  # about a kilobyte whenever a skill is added or removed, so a suite that went
  # red on that step would enforce nothing. The gap is printed.
  WORKING_SET_TARGET = 15_000

  DEFAULT_REPEAT = 5

  # Fixed inputs. The stale-intent line renders an age, so the fixture's future
  # intents are created this many days before *today*: the rendered "(30 days)"
  # is then a constant instead of a number that drifts with the calendar.
  FIXTURE_STALE_DAYS = 30
  FIXTURE_SESSION_ID = "plastic-context-bench"

  # What the fixture deliberately leaves out of the measurement, printed with the
  # table so a reader knows what the number does not cover.
  EXCLUSIONS = [
    "the update notice and the prior-day sweep line (both transient, absent from a steady-state boot)",
    "the harness's own system prompt and tool schemas (not Plastic's, and not readable from here)",
  ].freeze

  Measurement = Struct.new(:lines, :words, :tokens, :bytes, :tokens_by_bytes)

  # The token estimate is the word count times 1.3.
  # bytes / 4 is a second, independent estimate printed for cross-check. Neither
  # is a tokenizer; both are deterministic and offline.
  def self.measure(body)
    words = body.split(/\s+/).reject(&:empty?).length
    Measurement.new(body.lines.count, words, (words * 1.3).round,
                    body.bytesize, (body.bytesize / 4.0).round)
  end

  # Splits a skill at its frontmatter, so the frontmatter is counted once (in the
  # catalog row) and its body once (in the median-body row), never both.
  def self.split_skill(content)
    parts = content.split("---", 3)
    return [nil, content] if parts.length < 3

    [parts[1], parts[2]]
  end

  def self.skill_paths(repo:)
    Dir.glob(File.join(repo, "skills", "*", "SKILL.md")).sort
  end

  # What the harness loads at boot: every skill's name and description VALUES,
  # YAML-parsed. Not the raw frontmatter (that would count the keys and the
  # operational fields), and not a line regex (that would truncate a flattened
  # description at its first line).
  def self.skill_catalog_bytes(repo:)
    skill_paths(repo: repo).sum do |path|
      frontmatter, = split_skill(File.read(path))
      data = YAML.safe_load(frontmatter.to_s, permitted_classes: [Date, Time], aliases: true) || {}
      data["name"].to_s.bytesize + data["description"].to_s.bytesize
    end
  end

  def self.agent_paths(repo:)
    Dir.glob(File.join(repo, "agents", "*.md")).sort
  end

  # The agent catalog is the skill catalog's twin: the harness lists every agent's
  # name and description to the top-level session, whether or not one is ever
  # dispatched. Same YAML read as skill_catalog_bytes, for the same reason.
  def self.agent_catalog_bytes(repo:)
    agent_paths(repo: repo).sum { |path| agent_entry(path).bytesize }
  end

  def self.agent_catalog_text(repo:)
    agent_paths(repo: repo).map { |path| agent_entry(path) }.join
  end

  def self.agent_entry(path)
    frontmatter, = split_skill(File.read(path))
    data = YAML.safe_load(frontmatter.to_s, permitted_classes: [Date, Time], aliases: true) || {}
    "#{data["name"]}#{data["description"]}"
  end

  def self.skill_body_sizes(repo:)
    skill_paths(repo: repo).map do |path|
      _frontmatter, body = split_skill(File.read(path))
      body.bytesize
    end
  end

  def self.median(values)
    return 0 if values.empty?

    sorted = values.sort
    middle = sorted.length / 2
    return sorted[middle] if sorted.length.odd?

    ((sorted[middle - 1] + sorted[middle]) / 2.0).round
  end

  # A fixed Plastic home: a real install, then a fixed store on top of it.
  #
  # The install matters. A fixture without ~/.claude fails
  # Doctor#check_agent_registration (doctor_core.rb:307-314), which short-circuits
  # the rest of the core checks and renders the degraded banner, measuring a boot
  # no real session sees. Running the real installer costs about a quarter of a
  # second and gives `doctor --core run: success`.
  Fixture = Struct.new(:home, :plastic_home, :index, :project_dir, keyword_init: true) do
    def self.build(dir:, repo:, today: Date.today)
      ContextBudget.build_fixture(dir: dir, repo: repo, today: today)
    end
  end

  def self.build_fixture(dir:, repo:, today: Date.today)
    home = File.realpath(dir)
    plastic_home = File.join(home, ".plastic")
    FileUtils.mkdir_p(File.join(home, ".claude"))
    install_into(home: home, plastic_home: plastic_home, repo: repo)

    project_dir = File.join(home, "project")
    FileUtils.mkdir_p(project_dir)
    # On macOS Dir.pwd resolves /var to /private/var. The hook compares Dir.pwd
    # against the registered project path with start_with?, so an unresolved path
    # silently loses the project banner from the measured context.
    project_dir = File.realpath(project_dir)

    write_global_store(plastic_home: plastic_home, today: today)
    write_project_store(plastic_home: plastic_home, project_dir: project_dir, today: today)

    Fixture.new(home: home, plastic_home: plastic_home,
                index: File.join(Plastic::StoreLayout.global_root(plastic_home), "INDEX.md"), project_dir: project_dir)
  end

  def self.install_into(home:, plastic_home:, repo:)
    installer = File.join(repo, "scripts", "install.rb")
    raise "install: #{installer} not found; #{repo} is not a Plastic checkout" unless File.file?(installer)

    env = { "HOME" => home, "PLASTIC_HOME" => plastic_home, "RUBYOPT" => nil }
    out, err, status = Open3.capture3(env, RbConfig.ruby, installer, "--claude", chdir: repo)
    return if status.success?

    raise "install failed (exit #{status.exitstatus}): #{err.strip}#{out.strip}"
  end

  # Intent ids are written one call per intent, never as one array literal:
  # packaging_no_store_ids_test.rb flags any shipped literal carrying five or
  # more digit-leading tokens, and bin/ is inside package.json's files set.
  def self.write_global_store(plastic_home:, today:)
    store = Plastic::StoreLayout.global_store(plastic_home)
    write_intent(store, "0001", "a-global-intent-in-flight", 1, today)
    write_intent(store, "0002", "a-parked-global-intent", FIXTURE_STALE_DAYS, today)
    write_intent(store, "0003", "another-parked-global-intent", FIXTURE_STALE_DAYS, today)

    File.write(File.join(Plastic::StoreLayout.global_root(plastic_home), "INDEX.md"), <<~MD)
      # Index

      ## Active
      #{index_line("0001", "a-global-intent-in-flight", "a global intent that is being delivered right now")}

      ## Future
      #{index_line("0002", "a-parked-global-intent", "a parked global intent waiting on a ruling")}
      #{index_line("0003", "another-parked-global-intent", "another parked global intent waiting on a ruling")}
    MD
  end

  def self.write_project_store(plastic_home:, project_dir:, today:)
    project_root = Plastic::StoreLayout.project_root(plastic_home, "fixture")
    store = File.join(project_root, "store")
    write_intent(store, "0100", "a-project-intent-in-flight", 1, today)
    write_intent(store, "0101", "a-parked-project-intent", FIXTURE_STALE_DAYS, today)

    File.write(File.join(project_root, "INDEX.md"), <<~MD)
      # Index

      ## Active
      #{index_line("0100", "a-project-intent-in-flight", "a project intent that is being delivered right now")}

      ## Future
      #{index_line("0101", "a-parked-project-intent", "a parked project intent waiting for a decision")}
    MD

    registration = { "projects" => { "fixture" => { "path" => project_dir, "parent" => nil } } }
    File.write(File.join(plastic_home, "projects.yml"), YAML.dump(registration))
  end

  def self.index_line(id, slug, title)
    "- [#{id} — #{title}](store/#{id}--#{slug}/#{id}--#{slug}.md)"
  end

  def self.write_intent(store, id, slug, age_days, today)
    dir = File.join(store, "#{id}--#{slug}")
    FileUtils.mkdir_p(dir)
    File.write(File.join(dir, "#{id}--#{slug}.md"), <<~MD)
      ---
      id: "#{id}"
      created: #{(today - age_days).iso8601}
      author: bench
      ---

      ## Intent
      A fixed fixture intent, so the bench measures the same boot every time.
    MD
  end

  # The child environment is a pure function of the fixture, so a test can assert
  # containment without running anything.
  #
  # PATH is exactly the running interpreter's directory. The hook backticks
  # scripts/read-config three times and read-config's shebang is
  # `#!/usr/bin/env ruby`, so a PATH carrying /usr/bin would run those three
  # reads under the system Ruby while the report named a different one.
  def self.child_env(fixture)
    {
      "HOME" => fixture.home,
      "PLASTIC_HOME" => fixture.plastic_home,
      "PLASTIC_TMP" => File.join(fixture.home, "tmp"),
      "CLAUDE_CODE_SESSION_ID" => FIXTURE_SESSION_ID,
      "PATH" => File.dirname(RbConfig.ruby),
      "RUBYOPT" => nil,
    }
  end

  DEFAULT_RUNNER = lambda do |env, *command, **options|
    Open3.capture3(env, *command, **options)
  end

  # Runs the real hook once. Returns [additionalContext, elapsed_ms]. A failed or
  # empty boot raises rather than scoring as a small, passing number.
  #
  # The kernel registers no SessionStart hook yet, so no
  # repo on alpha ships scripts/hook-session-start any more. A repo without the
  # file boots to an empty context, deterministically, with no process spawned
  # and no runner call; the measurement reports the truth, that nothing runs.
  # A repo that still carries the file, real or a fixture built to simulate
  # one, boots for real through the injectable runner exactly as before.
  def self.boot(fixture:, repo:, runner: DEFAULT_RUNNER)
    hook = File.join(repo, "scripts", "hook-session-start")
    return ["", 0.0] unless File.file?(hook)

    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    out, err, status = runner.call(child_env(fixture), RbConfig.ruby, hook,
                                   fixture.index, fixture.plastic_home, "global", repo,
                                   chdir: fixture.project_dir)
    elapsed_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round(1)

    raise "boot failed (exit #{status.exitstatus}): #{err.strip}" unless status.success?
    raise "boot wrote to stderr: #{err.strip}" unless err.to_s.strip.empty?

    context = JSON.parse(out).dig("hookSpecificOutput", "additionalContext").to_s
    raise "boot emitted no additionalContext" if context.empty?

    [context, elapsed_ms]
  end

  Sample = Struct.new(:bytes, :ms, keyword_init: true)

  Row = Struct.new(:key, :label, :bytes, :tokens, :tokens_by_bytes, :ceiling, :target, keyword_init: true) do
    def enforced?
      !ceiling.nil?
    end

    # The ceiling is a strict bound: "under 8,192" means 8,192 itself is over.
    def over?
      enforced? && bytes >= ceiling
    end

    def headroom
      enforced? ? ceiling - bytes : nil
    end

    def gap
      target.nil? ? nil : bytes - target
    end
  end

  Report = Struct.new(:rows, :samples, :context, :repeat, :fragment, :ruby_version, :ruby_bin, keyword_init: true) do
    def row(key)
      rows.find { |candidate| candidate.key == key }
    end

    def byte_spread
      samples.map(&:bytes).max - samples.map(&:bytes).min
    end

    def failures
      crossed = rows.select(&:over?).map do |candidate|
        "#{candidate.key} (#{candidate.label}) is #{candidate.bytes} bytes; ceiling #{candidate.ceiling}"
      end
      return crossed if byte_spread.zero?

      crossed + ["byte spread across #{repeat} repeats is #{byte_spread}, expected 0"]
    end

    def ok?
      failures.empty?
    end

    def to_table
      ContextBudget.render(self)
    end

    def exit_status = ok? ? 0 : 1

    def print_to(out)
      out.print to_table
      exit_status
    end
  end

  # `fixture:` lets a caller that already built one, such as the bench's own
  # test suite, skip a second install and reuse it. It is never given a
  # `core_file`: the swap below is destructive, so a shared fixture only ever
  # reaches here with none.
  def self.run(repo:, repeat: DEFAULT_REPEAT, core_file: nil, dir: nil, fixture: nil, today: Date.today)
    unless repeat.is_a?(Integer) && repeat >= 1
      raise ArgumentError, "repeat must be an integer of at least 1 (got #{repeat.inspect})"
    end

    return report_for(fixture: fixture, repo: repo, repeat: repeat, core_file: core_file) if fixture

    if dir
      return report_for(fixture: Fixture.build(dir: dir, repo: repo, today: today), repo: repo, repeat: repeat,
        core_file: core_file)
    end

    Dir.mktmpdir("plastic-context-bench") do |tmp|
      report_for(fixture: Fixture.build(dir: tmp, repo: repo, today: today), repo: repo, repeat: repeat,
        core_file: core_file)
    end
  end

  def self.report_for(fixture:, repo:, repeat:, core_file:)
    # --core-file swaps the core block so a crossed ceiling can be observed
    # without editing a real file. check_core_files runs with include_drift:
    # false, so the swap does not change the banner.
    FileUtils.cp(core_file, File.join(fixture.plastic_home, "PLASTIC.md")) if core_file

    contexts = []
    samples = repeat.times.map do
      context, elapsed_ms = boot(fixture: fixture, repo: repo)
      contexts << context
      Sample.new(bytes: context.bytesize, ms: elapsed_ms)
    end

    Report.new(rows: build_rows(fixture: fixture, repo: repo, context: contexts.first),
               samples: samples, context: contexts.first, repeat: repeat,
               fragment: fragment_bytes(repo: repo),
               ruby_version: RUBY_VERSION, ruby_bin: RbConfig.ruby)
  end

def self.build_rows(fixture:, repo:, context:)
  core = measure(File.read(File.join(fixture.plastic_home, "PLASTIC.md")))
  boot_measurement = measure(context)
  catalog = measure(skill_catalog_text(repo: repo))
  agents = measure(agent_catalog_text(repo: repo))
  bodies = skill_body_sizes(repo: repo)
  median_body = median(bodies)
  fragment = fragment_bytes(repo: repo)

  combined = boot_measurement.bytes + catalog.bytes
  standing = core.bytes + boot_measurement.bytes + catalog.bytes + agents.bytes
  working_set = boot_measurement.bytes + fragment + median_body

  # tokens(w) is a word count of a real body, so the rows that are arithmetic
  # over other rows (a sum, a median) print "-" there rather than a number that
  # looks measured and is not. Every row still carries bytes and bytes / 4.
  [
    row(:core, "core block (PLASTIC.md)", core.bytes, tokens: core.tokens, ceiling: CEILINGS[:core]),
    row(:boot, "boot injection (SessionStart additionalContext)", boot_measurement.bytes,
        tokens: boot_measurement.tokens, ceiling: CEILINGS[:boot]),
    row(:skill_catalog, "skill catalog (#{bodies.length} name + description values)",
        catalog.bytes, tokens: catalog.tokens),
    row(:agent_catalog, "agent catalog (#{agent_paths(repo: repo).length} name + description values)",
        agents.bytes, tokens: agents.tokens),
    row(:boot_plus_catalog, "boot injection + skill catalog", combined,
        ceiling: CEILINGS[:boot_plus_catalog]),
    row(:standing, "standing surface (core + boot + both catalogs)", standing,
        ceiling: CEILINGS[:standing]),
    row(:median_skill_body, "median skill body (of #{bodies.length})", median_body),
    row(:working_set, "doctrine working set (boot + fragment + median body)",
        working_set, target: WORKING_SET_TARGET),
  ]
end

# The catalog as one body, so its word-token estimate is measured the same way
# every other body's is.
def self.skill_catalog_text(repo:)
  skill_paths(repo: repo).map do |path|
    frontmatter, = split_skill(File.read(path))
    data = YAML.safe_load(frontmatter.to_s, permitted_classes: [Date, Time], aliases: true) || {}
    "#{data["name"]}#{data["description"]}"
  end.join
end

  def self.fragment_bytes(repo:)
    path = File.join(repo, "skills", "_decision-tables.md")
    File.file?(path) ? File.size(path) : 0
  end

def self.row(key, label, bytes, tokens: nil, ceiling: nil, target: nil)
  Row.new(key: key, label: label, bytes: bytes, tokens: tokens,
          tokens_by_bytes: (bytes / 4.0).round, ceiling: ceiling, target: target)
end

  def self.render(report)
    byte_samples = report.samples.map(&:bytes)
    ms_samples = report.samples.map(&:ms)

    lines = []
    lines << "Plastic context budget bench"
    lines << ""
    lines << "  ruby      #{report.ruby_version}  (#{report.ruby_bin})"
    lines << "  repeats   #{report.repeat}  boot bytes min/median/max #{stat_line(byte_samples)}"
    lines << "  time      ms min/median/max #{stat_line(ms_samples)} - indicative only, never a pass/fail signal"
    lines << "  fixture   a real `scripts/install.rb --claude` into a temporary HOME, then a fixed store"
    lines << "            (1 active + 2 future global intents, 1 active + 1 future project intents)"
    lines << "  estimator words * 1.3 as tokens(w); bytes / 4 as tokens(b) - neither is a tokenizer"
    lines << ""
    lines << format("  %-52s %8s %9s %9s %9s %9s", "row", "bytes", "tokens(w)", "tokens(b)", "ceiling", "headroom")

    report.rows.each do |current|
      ceiling = current.enforced? ? current.ceiling.to_s : "reported"
      headroom = current.enforced? ? current.headroom.to_s : "-"
      lines << format("  %-52s %8d %9s %9d %9s %9s",
                      current.label, current.bytes, current.tokens || "-", current.tokens_by_bytes,
                      ceiling, headroom)
    end

    working_set = report.row(:working_set)
    if working_set&.target
      lines << ""
      lines << "  The doctrine working set is reported against the target of " \
               "#{working_set.target} bytes, not enforced:"
      lines << "  it stands at #{working_set.bytes} (#{format('%+d', working_set.gap)} against the target), " \
               "where the fragment is #{report.fragment} bytes."
      lines << "  Its median term steps by about a kilobyte whenever a skill is added or removed; " \
               "the skill bodies are the gap."
    end

    lines << ""
    lines << "  Not counted:"
    EXCLUSIONS.each { |exclusion| lines << "  - #{exclusion}" }

    lines << ""
    if report.ok?
      lines << "  PASS - every ceiling holds and the #{report.repeat} repeats are byte-identical."
    else
      lines << "  FAIL"
      report.failures.each { |failure| lines << "  - #{failure}" }
    end

    lines.join("\n") + "\n"
  end

  def self.stat_line(values)
    sorted = values.sort
    "#{sorted.first}/#{median_of_samples(sorted)}/#{sorted.last}"
  end

  def self.median_of_samples(sorted)
    middle = sorted.length / 2
    return sorted[middle] if sorted.length.odd?

    ((sorted[middle - 1] + sorted[middle]) / 2.0).round(1)
  end

  # bin/plastic-bench's own argv parsing and exit-code decision, as a class a
  # test can drive in-process. Only one scenario (the ceiling-crossed exit
  # code) still needs a real spawn of the executable; every other argument
  # case is this class's own behavior, not the process boundary.
  class CLI
    # Raised when argv names an unknown flag, or a flag's value fails its own check.
    UsageError = Class.new(StandardError)

    USAGE = <<~TEXT
      usage: plastic-bench [--repeat N] [--core-file PATH] [--repo PATH]

        --repeat N        boots to run against the fixture (default #{DEFAULT_REPEAT}, minimum 1)
        --core-file PATH  measure this file as the core block instead of PLASTIC.md
        --repo PATH       the Plastic checkout to measure (default: this checkout)
        --help            this message

      Exits 0 when every ceiling holds, 1 when one is crossed, 2 on bad usage.
    TEXT

    # Where the CLI prints to and which checkout it measures by default.
    IO = Struct.new(:out, :err, :default_repo, keyword_init: true)

    def self.run(argv, io = IO.new(out: $stdout, err: $stderr, default_repo: File.expand_path("../..", __dir__)),
      fixture: nil)
      new(argv, io, fixture:).call
    end

    # `fixture:` carries no argv flag; it exists only so the bench's own
    # tests can run the CLI's parsing and formatting against an install
    # they already paid for, the same contract a real call gets with a
    # fresh one.
    def initialize(argv, io, fixture: nil)
      @argv = argv
      @io = io
      @fixture = fixture
    end

    def call
      run
    rescue UsageError => error
      usage_error(error)
    rescue => error
      runtime_error(error)
    end

    private

    def run
      request = Args.parse(@argv, default_repo: @io.default_repo)
      return show_help if request.help

      run_report(request)
    end

    def run_report(request)
      ContextBudget.run(**request.run_kwargs, fixture: @fixture).print_to(@io.out)
    end

    def usage_error(error)
      print_error(error)
      @io.err.puts USAGE
      2
    end

    def runtime_error(error)
      print_error(error)
      1
    end

    def print_error(error)
      @io.err.puts "plastic-bench: #{error.message}"
    end

    def show_help
      @io.out.puts USAGE
      0
    end

    # Parses plastic-bench's argv into a Request, one flag at a time.
    class Args
      # The three run inputs argv resolves to: how many times to boot, which
      # file stands in for the core block, which checkout to measure.
      Request = Struct.new(:repeat, :core_file, :repo, :help, keyword_init: true) do
        def run_kwargs = { repeat: repeat, core_file: core_file, repo: repo }
      end

      FLAG_METHODS = {
        "--help" => :mark_help,
        "-h" => :mark_help,
        "--repeat" => :set_repeat,
        "--core-file" => :set_core_file,
        "--repo" => :set_repo
      }.freeze

      def self.parse(argv, default_repo:)
        new(argv, default_repo).parse
      end

      def initialize(argv, default_repo)
        @argv = argv.dup
        @request = Request.new(repeat: DEFAULT_REPEAT, core_file: nil, repo: default_repo, help: false)
      end

      def parse
        apply_flag(@argv.shift) until @argv.empty?
        @request
      end

      private

      def apply_flag(flag)
        send(FLAG_METHODS.fetch(flag) { raise UsageError, "unknown argument #{flag}" })
      end

      def mark_help = @request.help = true

      def set_repeat = @request.repeat = repeat_value

      def set_core_file = @request.core_file = core_file_value

      def set_repo = @request.repo = repo_value

      def repeat_value
        value = @argv.shift
        count = value.to_s.match?(/\A\d+\z/) ? value.to_i : 0
        raise UsageError, "--repeat needs a whole number of at least 1" if count < 1

        count
      end

      def core_file_value
        path = @argv.shift
        raise UsageError, "--core-file needs a path" if path.to_s.empty?
        raise UsageError, "--core-file #{path} does not exist" unless File.file?(path)

        path
      end

      def repo_value
        path = @argv.shift
        raise UsageError, "--repo needs a path" if path.to_s.empty?
        raise UsageError, "--repo #{path} is not a directory" unless File.directory?(path)

        path
      end
    end
  end
end
