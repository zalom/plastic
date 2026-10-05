# encoding: UTF-8
# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"

# The refused word leaves every path Plastic keeps in this repository. Every
# planted sample is built from parts at runtime, so this file carries no hit.
class VocabularyScanTest < Minitest::Test
  REPO = File.expand_path("..", __dir__)

  SCANNED_PATHS = %w[scripts hooks agents skills templates bin test docs PLASTIC.md].freeze

  # Two segment rules (n6, B4), combined so each keeps its own case
  # sensitivity (Regexp.union wraps each branch in its own (?i-mx:...), so
  # the CamelCase branch never inherits the snake/kebab branch's /i - putting
  # it under one shared case-insensitive flag is exactly the trap that makes
  # "ffold" in scaffold match).
  #
  # Snake/kebab: case-insensitive, a refused form bounded on both sides by a
  # non-letter (start, end, underscore, hyphen, digit, dot, space, or any
  # other non-letter). Implemented as "not preceded/followed by a letter"
  # rather than \b, since \b treats underscore as a word character and never
  # matches inside snake_case.
  SNAKE_KEBAB = /(?<![a-zA-Z])f(?:old|olds|olded|olding)(?![a-zA-Z])/i
  # CamelCase: case-sensitive, a capital F plus a refused suffix, preceded by
  # a lowercase letter or digit, followed by end or a non-lowercase
  # character.
  CAMEL = /(?<=[a-z0-9])F(?:old|olds|olded|olding)(?![a-z])/
  REFUSED = Regexp.union(SNAKE_KEBAB, CAMEL)

  def self.offenders(root, files)
    hits = []
    files.each do |rel|
      hits << "#{rel}:0" if rel.match?(REFUSED)
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

  def test_the_scanned_tree_is_not_empty
    refute_empty scanned_files
  end

  def test_no_refused_word_in_the_shipped_tree
    offenders = self.class.offenders(REPO, scanned_files)

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

  def test_scan_refuses_snake_case_and_camel_case_segments
    Dir.mktmpdir("vocabulary-scan-identifiers") do |dir|
      File.write(File.join(dir, "snake.rb"), "value = review_#{"f" + "old"}\n")
      File.write(File.join(dir, "camel.rb"), "class Review#{"F" + "old"}Node; end\n")

      assert_equal %w[camel.rb:1 snake.rb:1], self.class.offenders(dir, %w[snake.rb camel.rb]).sort
    end
  end

  def test_scan_refuses_a_file_name_that_carries_the_word
    Dir.mktmpdir("vocabulary-scan-file-name") do |dir|
      name = "x_#{"f" + "olded"}_test.rb"
      File.write(File.join(dir, name), "nothing refused in the content\n")

      assert_equal ["#{name}:0"], self.class.offenders(dir, [name])
    end
  end

  def test_scan_leaves_scaffold_folder_and_manifold_identifiers_alone
    Dir.mktmpdir("vocabulary-scan-clean-identifiers") do |dir|
      File.write(File.join(dir, "clean.rb"), "def scaffold_intent = ScaffoldIntent.new\n# scaffold-intent, Folder, unfolding, manifold\n")
      names = %w[clean.rb scaffold_intent.rb scaffold-intent ScaffoldIntent]
      names.drop(1).each { |name| File.write(File.join(dir, name), "clean\n") }

      assert_empty self.class.offenders(dir, names)
    end
  end

  private

  # Built from parts so this source file carries no whole-word hit itself.
  def refused_sample
    "a line that says the plan was " + "f" + "old" + "ed" + " in review"
  end

  def scanned_files
    SCANNED_PATHS.flat_map do |rel|
      path = File.join(REPO, rel)
      next [rel] if File.file?(path)

      Dir.glob("**/*", File::FNM_DOTMATCH, base: path).map { |child| File.join(rel, child) }
        .select { |child| File.file?(File.join(REPO, child)) }
    end
  end
end
