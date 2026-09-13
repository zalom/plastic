# encoding: UTF-8
# frozen_string_literal: true

require "minitest/autorun"
require "open3"
require "tmpdir"

# Intent 337a (n4): the refused word leaves every path Plastic keeps in this
# repository, not only the seven npm publishes. This widens n3's shape
# (subtraction_304_test's forbidden-grammar walk) to cover `test` and `docs`
# too, and adds the matrix that keeps the scan itself honest: no exception
# list, a real path:line report, a whole-word match, and a cheap in-process
# walk. Every planted sample below is built from parts at runtime so this
# file carries no whole-word hit of its own.
class VocabularyScanTest < Minitest::Test
  REPO = File.expand_path("..", __dir__)

  SCANNED_PATHS = %w[scripts hooks agents skills templates bin test docs PLASTIC.md].freeze

  # Grouped so the word boundary binds the whole alternation, not just the first
  # and last branches (each branch is bounded on both ends this way).
  REFUSED = /\bf(?:old|olds|olded|olding)\b/i

  def self.offenders(root, files)
    hits = []
    files.each do |rel|
      path = File.join(root, rel)
      next unless File.file?(path)
      raw = File.binread(path)
      text = raw.encode("UTF-8", invalid: :replace, undef: :replace, replace: "")
      text.each_line.with_index(1) do |line, n|
        next unless line.match?(REFUSED)
        hits << "#{rel}:#{n}"
      end
    end
    hits
  end

  def test_no_refused_word_in_the_shipped_tree
    offenders = self.class.offenders(REPO, tracked_files)
    assert_empty offenders,
      "refused word survives (#{offenders.size}):\n#{offenders.first(30).join("\n")}"
  end

  def test_the_scan_has_no_exception_list
    banned_name = /skip|except|exclud|allow/i
    self.class.constants(false).each do |name|
      refute_match banned_name, name.to_s,
        "the scan must carry no exception-list constant, found #{name}"
    end

    Dir.mktmpdir("vocabulary-scan-no-skip") do |dir|
      names = (1..5).map { |i| "file_#{i}.txt" }
      names.each { |name| File.write(File.join(dir, name), "line one\n#{refused_sample}\n") }

      offenders = self.class.offenders(dir, names)
      touched = offenders.map { |hit| hit.split(":").first }.uniq.sort
      assert_equal names.sort, touched, "the scan must read every listed file, skipping none"
    end
  end

  def test_offenders_are_reported_with_path_and_line
    Dir.mktmpdir("vocabulary-scan-format") do |dir|
      File.write(File.join(dir, "a.md"), "clean line\n#{refused_sample}\n")
      File.write(File.join(dir, "b.md"), "#{refused_sample}\nclean line\nclean line\n")

      offenders = self.class.offenders(dir, %w[a.md b.md])
      assert_equal 2, offenders.size
      assert_equal %w[a.md:2 b.md:1], offenders.sort
    end
  end

  def test_scan_fails_on_a_planted_occurrence
    Dir.mktmpdir("vocabulary-scan-planted") do |dir|
      File.write(File.join(dir, "planted.md"), refused_sample)
      offenders = self.class.offenders(dir, %w[planted.md])
      refute_empty offenders, "the scan must fail on a planted occurrence, not walk an empty list"
    end
  end

  def test_whole_word_match_leaves_scaffold_and_folgezettel_alone
    Dir.mktmpdir("vocabulary-scan-boundary") do |dir|
      File.write(File.join(dir, "clean.md"), <<~TEXT)
        The scaffold stays up while the Folgezettel numbering settles.
        Move the export into its own folder, unfolding the archive as you go.
      TEXT
      offenders = self.class.offenders(dir, %w[clean.md])
      assert_empty offenders, "a whole-word scan must not flag scaffold, Folgezettel, folder or unfolding"
    end
  end

  def test_scan_completes_within_its_budget
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    self.class.offenders(REPO, tracked_files)
    elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
    assert_operator elapsed, :<, 5.0,
      "the scan must stay cheap enough to run on every commit (took #{elapsed.round(2)}s)"
  end

  private

  # Built from parts so this source file carries no whole-word hit itself.
  def refused_sample
    "a line that says the plan was " + "f" + "old" + "ed" + " in review"
  end

  def tracked_files
    out, _err, status = Open3.capture3("git", "-C", REPO, "ls-files", *SCANNED_PATHS)
    raise "git ls-files failed" unless status.success?
    out.lines.map(&:chomp).reject(&:empty?)
  end
end
