# encoding: UTF-8
# frozen_string_literal: true

require "date"
require "fileutils"
require "json"
require "open3"
require "rbconfig"
require "tmpdir"
require "yaml"

# ContextBudget (intent 313): the measurement behind Plastic's two ruled context
# numbers. Intent 296 ruled the core block under 8,192 bytes and the whole
# per-boot doctrine read under 15,000, and until this module both were estimates
# in a design document. Everything here is measured: the bench builds a fixture
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
  # The two ruled ceilings (intent 296) plus the one ratchet intent 313 adds.
  #
  #   core              PLASTIC.md, the always-on core block. 296's ruling.
  #   boot              the additionalContext hook-session-start emits. 296's
  #                     whole-read ruling, enforced on the only quantity that is
  #                     actually read on every boot and can be measured exactly.
  #   boot_plus_catalog boot injection plus the skill catalog the harness loads.
  #                     Not a ruling: a 313 ratchet over the measured 16,537, so
  #                     the second-largest per-boot cost cannot regrow unwatched.
  #                     Lower it as the catalog shrinks; never raise it.
  CEILINGS = { core: 8_192, boot: 15_000, boot_plus_catalog: 17_500 }.freeze

  # The doctrine working set (boot + _decision-tables.md + the median skill body)
  # is reported against this target, never enforced: its median term steps by
  # about a kilobyte whenever a skill is added or removed, so a suite that went
  # red on that step would enforce nothing anybody ruled. The gap is printed.
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
    "the QMD status line (PATH carries only the running interpreter's directory, so qmd is unfindable on any host)",
    "the harness's own system prompt and tool schemas (not Plastic's, and not readable from here)",
  ].freeze

  Measurement = Struct.new(:lines, :words, :tokens, :bytes, :tokens_by_bytes)

  # The word-based token estimate is skill_lint.rb:104's arithmetic exactly, so
  # the bench and skill-lint can never report different numbers for one file.
  # bytes / 4 is a second, independent estimate printed for cross-check. Neither
  # is a tokenizer; both are deterministic and offline.
  def self.measure(body)
    words = body.split(/\s+/).reject(&:empty?).length
    Measurement.new(body.lines.count, words, (words * 1.3).round,
                    body.bytesize, (body.bytesize / 4.0).round)
  end

  # skill_lint.rb:82-90's split, so a skill's frontmatter is counted once (in the
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
  # operational fields), and not a line regex (that would truncate a folded
  # description at its first line).
  def self.skill_catalog_bytes(repo:)
    skill_paths(repo: repo).sum do |path|
      frontmatter, = split_skill(File.read(path))
      data = YAML.safe_load(frontmatter.to_s, permitted_classes: [Date, Time], aliases: true) || {}
      data["name"].to_s.bytesize + data["description"].to_s.bytesize
    end
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
                index: File.join(plastic_home, "INDEX.md"), project_dir: project_dir)
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
    store = File.join(plastic_home, "store")
    write_intent(store, "0001", "a-global-intent-in-flight", 1, today)
    write_intent(store, "0002", "a-parked-global-intent", FIXTURE_STALE_DAYS, today)
    write_intent(store, "0003", "another-parked-global-intent", FIXTURE_STALE_DAYS, today)

    File.write(File.join(plastic_home, "INDEX.md"), <<~MD)
      # Index

      ## Active
      #{index_line("0001", "a-global-intent-in-flight", "a global intent that is being delivered right now")}

      ## Future
      #{index_line("0002", "a-parked-global-intent", "a parked global intent waiting on a ruling")}
      #{index_line("0003", "another-parked-global-intent", "another parked global intent waiting on a ruling")}
    MD
  end

  def self.write_project_store(plastic_home:, project_dir:, today:)
    project_root = File.join(plastic_home, "projects", "fixture")
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
  # PATH is exactly the running interpreter's directory, and that is load-bearing
  # twice. The hook backticks scripts/read-config three times and read-config's
  # shebang is `#!/usr/bin/env ruby`, so a PATH carrying /usr/bin would run those
  # three reads under the system Ruby while the report named a different one. And
  # with nothing else on PATH, `qmd` cannot be found on any host, so the QMD
  # status line never appears and the measurement reproduces off this machine.
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
  def self.boot(fixture:, repo:, runner: DEFAULT_RUNNER)
    hook = File.join(repo, "scripts", "hook-session-start")
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
  end

  def self.run(repo:, repeat: DEFAULT_REPEAT, core_file: nil, dir: nil, today: Date.today)
    unless repeat.is_a?(Integer) && repeat >= 1
      raise ArgumentError, "repeat must be an integer of at least 1 (got #{repeat.inspect})"
    end

    return report_for(dir: dir, repo: repo, repeat: repeat, core_file: core_file, today: today) if dir

    Dir.mktmpdir("plastic-context-bench") do |tmp|
      report_for(dir: tmp, repo: repo, repeat: repeat, core_file: core_file, today: today)
    end
  end

  def self.report_for(dir:, repo:, repeat:, core_file:, today:)
    fixture = Fixture.build(dir: dir, repo: repo, today: today)
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
  bodies = skill_body_sizes(repo: repo)
  median_body = median(bodies)
  fragment = fragment_bytes(repo: repo)

  combined = boot_measurement.bytes + catalog.bytes
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
    row(:boot_plus_catalog, "boot injection + skill catalog", combined,
        ceiling: CEILINGS[:boot_plus_catalog]),
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
    lines << "Plastic context budget bench (intent 313)"
    lines << ""
    lines << "  ruby      #{report.ruby_version}  (#{report.ruby_bin})"
    lines << "  repeats   #{report.repeat}  boot bytes min/median/max #{stat_line(byte_samples)}"
    lines << "  time      ms min/median/max #{stat_line(ms_samples)} - indicative only, never a pass/fail signal"
    lines << "  fixture   a real `scripts/install.rb --claude` into a temporary HOME, then a fixed store"
    lines << "            (1 active + 2 future global intents, 1 active + 1 future project intents)"
    lines << "  estimator words * 1.3 (skill-lint's arithmetic) as tokens(w); bytes / 4 as tokens(b) - neither is a tokenizer"
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
      lines << "  The doctrine working set is reported against intent 296's ruled target of " \
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
end
