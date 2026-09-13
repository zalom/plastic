# encoding: UTF-8
# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "digest"
require "time"

require_relative "../scripts/lib/node_ledger"
require_relative "../scripts/lib/node_input_compatibility"
require_relative "../scripts/lib/node_packet"
require_relative "../scripts/lib/packet_wrapper"
require_relative "../scripts/lib/ready_set"
require_relative "../scripts/lib/graph_measure_budget"

# GraphMeasureBudgetTest (intent 343, G10, n4): the budget ceiling (C19) and
# the token estimate the packet builder actually enforced. Matrix rows
# 4.1-4.11 in nodes/n4.md.
#
# Rows 4.5, 4.7 and 4.8 read the real intent 340 fixture (never authored by
# this test, spec D18's rule the other way round: a row a real ledger DOES
# produce gets checked against that real ledger, not a stand-in). Every
# other row builds its own hermetic fixture in a Dir.mktmpdir, including a
# real packets/ directory with real files this test writes and hashes
# itself, because GraphMeasureBudget resolves and verifies actual bytes on
# disk (spec D1's "budget: read by G10").
class GraphMeasureBudgetTest < Minitest::Test
  FIXTURES = File.expand_path("fixtures/ledgers", __dir__)
  DIR_340 = File.join(FIXTURES, "340--runner-core-in-session")

  def with_intent_dir
    Dir.mktmpdir("graph-measure-budget-test") do |dir|
      yield dir
    end
  end

  def stamp(str)
    Time.iso8601(str)
  end

  def transition(ts, subject, state, fields: {}, comment: nil)
    NodeLedger.transition_line(subject: subject, state: state, fields: fields, comment: comment, now: ts)
  end

  def write_savepoint(dir, lines)
    File.write(File.join(dir, "savepoint.md"), Array(lines).join)
  end

  # budget: nil omits the field entirely (row 4.2's absent-budget case);
  # any other value is written as a bare integer (NodeFile's normal form).
  def write_node_file(dir, id, kind, budget:)
    FileUtils.mkdir_p(File.join(dir, "nodes"))
    budget_line = budget.nil? ? "" : "budget: #{budget}\n"
    File.write(File.join(dir, "nodes", "#{id}.md"), <<~MD)
      ---
      node: #{id}
      kind: #{kind}
      files: []
      #{budget_line}---
      # #{id}
      body
    MD
  end

  # Writes a real packets/<node>--a<attempt>.packet file and returns its real
  # sha256[0,12], the same function NodePacket itself uses to mint input=.
  def write_packet(dir, node, attempt, content)
    packets_dir = File.join(dir, "packets")
    FileUtils.mkdir_p(packets_dir)
    path = File.join(packets_dir, "#{node}--a#{attempt}.packet")
    File.write(path, content)
    Digest::SHA256.hexdigest(File.binread(path))[0, 12]
  end

  RUNNING = { holder: "auto-1", expires: "2099-01-01T00:00:00Z", model: "sonnet" }.freeze

  # --- 4.1: declared budget read from the envelope -----------------------------

  def test_declared_budget_read_from_the_envelope
    with_intent_dir do |dir|
      write_node_file(dir, "n1", "work", budget: 120_000)
      sha = write_packet(dir, "n1", 1, "x" * 400)
      write_savepoint(dir, [transition(stamp("2026-01-01T09:00:00Z"), "n1", "running",
                                        fields: RUNNING.merge(input: sha))])

      record = GraphMeasureBudget.read(dir)
      assert_equal 120_000, record[:nodes]["n1"][:declared_budget]
    end
  end

  # --- 4.2: absent budget is unavailable, never zero ---------------------------

  def test_absent_budget_is_unavailable_not_zero
    with_intent_dir do |dir|
      write_node_file(dir, "n1", "work", budget: nil)
      sha = write_packet(dir, "n1", 1, "x" * 400)
      write_savepoint(dir, [transition(stamp("2026-01-01T09:00:00Z"), "n1", "running",
                                        fields: RUNNING.merge(input: sha))])

      record = GraphMeasureBudget.read(dir)
      assert_equal :unavailable, record[:nodes]["n1"][:declared_budget]
      refute_equal 0, record[:nodes]["n1"][:declared_budget]
    end
  end

  # --- 4.3: resolved by NodePacket.packet_path, not a sha-named file -----------

  def test_packet_resolved_by_path_not_by_sha_name
    with_intent_dir do |dir|
      write_node_file(dir, "n1", "work", budget: 120_000)
      real_sha = write_packet(dir, "n1", 1, "y" * 800)
      # A decoy file named after the sha itself. If the reader ever searched
      # for a sha-named file instead of resolving by path, it would find
      # this file's (wrong) size instead.
      File.write(File.join(dir, "packets", "#{real_sha}.packet"), "z" * 40)
      write_savepoint(dir, [transition(stamp("2026-01-01T09:00:00Z"), "n1", "running",
                                        fields: RUNNING.merge(input: real_sha))])

      record = GraphMeasureBudget.read(dir)
      attempt = record[:nodes]["n1"][:attempts].first
      assert_equal 800, attempt[:bytes]
    end
  end

  # --- 4.4: sha verified against the running line's input= ---------------------

  def test_packet_sha_verified_against_the_running_line
    with_intent_dir do |dir|
      write_node_file(dir, "n1", "work", budget: 120_000)
      write_packet(dir, "n1", 1, "a" * 400)
      declared_sha = "deadbeefcafe"
      write_savepoint(dir, [transition(stamp("2026-01-01T09:00:00Z"), "n1", "running",
                                        fields: RUNNING.merge(input: declared_sha))])

      record = GraphMeasureBudget.read(dir)
      attempt = record[:nodes]["n1"][:attempts].first
      assert attempt[:file_exists]
      refute attempt[:sha_match]
      refute_equal declared_sha, attempt[:packet_sha_actual]
    end
  end

  # --- 338a n1, 1.15: the declared sha reads from a legacy running line ------

  def test_declared_sha_reads_from_a_legacy_running_line
    with_intent_dir do |dir|
      write_node_file(dir, "n1", "work", budget: 120_000)
      sha = write_packet(dir, "n1", 1, "x" * 400)
      legacy_line = "2026-01-01T09:00:00Z  n1  running holder=auto-1 expires=2099-01-01T00:00:00Z " \
                    "#{NodeInputCompatibility::LEGACY_FIELD}=#{sha} model=sonnet\n"
      write_savepoint(dir, [legacy_line])

      record = GraphMeasureBudget.read(dir)
      attempt = record[:nodes]["n1"][:attempts].first
      assert_equal sha, attempt[:packet_sha_declared]
      assert attempt[:sha_match]
    end
  end

  # --- 4.5: attempt numbering follows NodePacket, never ReadySet ---------------

  def test_attempt_numbering_follows_node_packet_not_ready_set
    record = GraphMeasureBudget.read(DIR_340)
    attempts = record[:nodes]["n6"][:attempts]
    assert_equal [1, 2, 3], attempts.map { |a| a[:attempt] }

    full_entries = NodeLedger.entries(File.join(DIR_340, "savepoint.md"))
    assert_equal 0, ReadySet.attempts_count(full_entries, "n6"),
                 "ReadySet.attempts_count resets after n6's terminal done line; " \
                 "it cannot be used to number the attempt a past running line was"
  end

  # --- 4.6: tokens via PacketWrapper.estimate_tokens, raw bytes beside it ------

  def test_token_estimate_reuses_packet_wrapper
    with_intent_dir do |dir|
      write_node_file(dir, "n1", "work", budget: 120_000)
      # 402 bytes: (402 / 4.0).round is 101, while a naive integer division
      # (402 / 4) floors to 100 - the two formulas disagree here on purpose,
      # so a hand-rolled second formula would be caught rather than pass by
      # coincidence.
      content = "x" * 402
      sha = write_packet(dir, "n1", 1, content)
      write_savepoint(dir, [transition(stamp("2026-01-01T09:00:00Z"), "n1", "running",
                                        fields: RUNNING.merge(input: sha))])

      record = GraphMeasureBudget.read(dir)
      attempt = record[:nodes]["n1"][:attempts].first
      assert_equal 402, attempt[:bytes]
      assert_equal 101, attempt[:estimate_tokens]
      assert_equal PacketWrapper.estimate_tokens(content), attempt[:estimate_tokens]
    end
  end

  # --- 4.7: hop subtracted before the budget comparison -------------------------

  def test_hop_subtracted_before_the_budget_comparison
    record = GraphMeasureBudget.read(DIR_340)
    a3 = record[:nodes]["n6"][:attempts][2]

    assert_equal 3, a3[:attempt]
    assert_equal 35_780, a3[:bytes]
    assert_equal 8_945, a3[:estimate_tokens]
    assert_equal 2000, a3[:hop]
    assert_equal 6_945, a3[:effective_tokens]
    refute a3[:over_budget], "6,945 effective tokens is well under n6's declared 140,000 budget"
  end

  # --- 4.8: packets under a common ceiling report it by value -------------------

  def test_packets_under_a_common_ceiling_report_it_by_value
    record = GraphMeasureBudget.read(DIR_340)
    ceiling = record[:ceiling]

    assert_equal true, ceiling[:detected]
    assert_equal 7717, ceiling[:value]
    assert_equal 14, ceiling[:node_count]
    assert_equal 16, ceiling[:attempt_count]
  end

  # --- 9.2 (v2 NEW-2): the ceiling rule separates four pinned cases (D21) -------

  # v2's own review (resources/review--v2-2026-09-12.md, NEW-2): the old rule
  # reported the largest observed packet as a ceiling whenever every usable
  # attempt's own declared budget was merely generous, and missed a genuine
  # shared ceiling whenever declared budgets were tight. Reproduced by hand
  # before this fix, against the exact numbers v2 named: two nodes at 3000
  # and 7000 effective tokens against a declared 100000 each, plus one at
  # 1200 against 150000, reported "detected: true, value: 7000" though only
  # one attempt anywhere sits near that candidate; three nodes converging
  # tightly on 7717/7690/7650 against a declared 10000 each - a real shared
  # ceiling - reported "not_well_below_declared_budgets"; and two nodes
  # declaring a budget of 0 with 0 effective tokens each reported "detected:
  # true, value: 0" rather than the disqualification D21 requires for an
  # absent or zero declared budget.
  def test_ceiling_rule_separates_the_four_pinned_cases
    real = GraphMeasureBudget.read(DIR_340)
    assert real[:ceiling][:detected], "340's real packets cluster far under their own declared budgets"
    assert_equal 7717, real[:ceiling][:value]

    generous_no_cluster = {
      "n1" => { declared_budget: 100_000, attempts: [{ effective_tokens: 3000 }] },
      "n2" => { declared_budget: 100_000, attempts: [{ effective_tokens: 7000 }] },
      "n3" => { declared_budget: 150_000, attempts: [{ effective_tokens: 1200 }] },
    }
    no_cluster = GraphMeasureBudget.send(:detect_ceiling, generous_no_cluster)
    refute no_cluster[:detected],
           "one high value with no other attempt approaching it from below is not a shared ceiling, " \
           "no matter how generous the declared budgets are"

    tight_shared_ceiling = {
      "n1" => { declared_budget: 10_000, attempts: [{ effective_tokens: 7717 }] },
      "n2" => { declared_budget: 10_000, attempts: [{ effective_tokens: 7690 }] },
      "n3" => { declared_budget: 10_000, attempts: [{ effective_tokens: 7650 }] },
    }
    tight = GraphMeasureBudget.send(:detect_ceiling, tight_shared_ceiling)
    assert tight[:detected],
           "three distinct nodes converging tightly on the same value is the evidence D21 asks for, " \
           "even under a tight declared budget"
    assert_equal 7717, tight[:value]

    all_zero = {
      "n1" => { declared_budget: 0, attempts: [{ effective_tokens: 0 }] },
      "n2" => { declared_budget: 0, attempts: [{ effective_tokens: 0 }] },
    }
    zero = GraphMeasureBudget.send(:detect_ceiling, all_zero)
    refute zero[:detected], "an attempt with no declared budget is disqualified, never read as a zero ceiling"
    assert_nil zero[:value]
  end

  # --- 10.2 (v3 M1): a cluster needs SEVERAL_CLUSTER_THRESHOLD nodes, not two ----

  # v3's own review (resources/review--v3-2026-09-12.md, M1): the existence
  # test at the old `graph_measure_budget.rb:349` accepted two nodes, so any
  # two packets within twenty percent of each other formed a "cluster" and
  # the candidate was still `max(effective)`. Reproduced by hand before this
  # fix, against the exact shape v3 named: two nodes at 6000 and 7000
  # effective tokens against a declared 100000 each, plus one at 1200
  # against 150000, reported "detected: true, value: 7000" though only the
  # two-node pair sits anywhere near that number. Reproduced again against
  # 340's own real table: the n1+n2 subset alone reported "detected: true,
  # value: 6295", a number the full 14-node table's real ceiling (7717)
  # never produces.
  def test_two_nodes_within_the_band_are_not_several
    two_of_three = {
      "n1" => { declared_budget: 100_000, attempts: [{ effective_tokens: 6000 }] },
      "n2" => { declared_budget: 100_000, attempts: [{ effective_tokens: 7000 }] },
      "n3" => { declared_budget: 150_000, attempts: [{ effective_tokens: 1200 }] },
    }
    ceiling = GraphMeasureBudget.send(:detect_ceiling, two_of_three)
    refute ceiling[:detected],
           "two nodes converging within the band are not \"several\" distinct usable attempts (D21, D25); " \
           "a two-node band is not the evidence a shared ceiling needs"

    record = GraphMeasureBudget.read(DIR_340)
    n1_n2 = record[:nodes].select { |id, _| %w[n1 n2].include?(id) }
    subset = GraphMeasureBudget.send(:detect_ceiling, n1_n2)
    refute subset[:detected],
           "340's own n1+n2 subset is a two-node band; it must not report a ceiling the full 14-node " \
           "table's own real ceiling (7717) never produces"
  end

  # --- 10.3 (v3 M2): the clustered well-below ratio is 0.8, not 0.9 -------------

  # v3's own review (M2): `CLUSTERED_WELL_BELOW_RATIO = 0.9` let a cluster at
  # ninety percent of its declared budget report a ceiling, the case where
  # the declared budget IS the ceiling, the opposite of what C19 asks.
  # Reproduced by hand before this fix: three nodes at 9000, 8990 and 8980
  # against a declared 10000 each reported "detected: true, value: 9000".
  # D25 rules "far under" at 0.8, which the four D21 pinned cases (asserted
  # above and in test_ceiling_rule_separates_the_four_pinned_cases) still
  # separate correctly.
  def test_a_cluster_at_ninety_percent_of_its_budget_is_not_a_ceiling
    ninety_percent = {
      "n1" => { declared_budget: 10_000, attempts: [{ effective_tokens: 9000 }] },
      "n2" => { declared_budget: 10_000, attempts: [{ effective_tokens: 8990 }] },
      "n3" => { declared_budget: 10_000, attempts: [{ effective_tokens: 8980 }] },
    }
    ceiling = GraphMeasureBudget.send(:detect_ceiling, ninety_percent)
    refute ceiling[:detected],
           "ninety percent utilisation of the declared budget is the case where the declared budget IS " \
           "the ceiling, not evidence of one sitting under it (D21, D25)"
    assert_equal :not_well_below_declared_budgets, ceiling[:reason]

    eighty_percent = {
      "n1" => { declared_budget: 10_000, attempts: [{ effective_tokens: 8000 }] },
      "n2" => { declared_budget: 10_000, attempts: [{ effective_tokens: 7990 }] },
      "n3" => { declared_budget: 10_000, attempts: [{ effective_tokens: 7980 }] },
    }
    at_ratio = GraphMeasureBudget.send(:detect_ceiling, eighty_percent)
    assert at_ratio[:detected], "eighty percent of the declared budget is exactly D25's \"far under\" bar"
  end

  # --- 4.9: a single node never reports a ceiling --------------------------------

  def test_single_node_never_reports_a_ceiling
    with_intent_dir do |dir|
      write_node_file(dir, "n1", "work", budget: 120_000)
      sha1 = write_packet(dir, "n1", 1, "x" * 400)
      sha2 = write_packet(dir, "n1", 2, "x" * 800)
      write_savepoint(dir, [
        transition(stamp("2026-01-01T09:00:00Z"), "n1", "running", fields: RUNNING.merge(input: sha1)),
        transition(stamp("2026-01-01T09:05:00Z"), "n1", "failed_verification",
                   fields: { holder: "auto-1", model: "sonnet", gates: "suite", reason: "red" }),
        transition(stamp("2026-01-01T09:06:00Z"), "n1", "running", fields: RUNNING.merge(input: sha2)),
      ])

      record = GraphMeasureBudget.read(dir)
      refute record[:ceiling][:detected]
      assert_equal 1, record[:ceiling][:node_count]
    end
  end

  # --- 4.10: an over-budget node is flagged --------------------------------------

  def test_over_budget_node_is_flagged
    with_intent_dir do |dir|
      write_node_file(dir, "n1", "work", budget: 50)
      sha = write_packet(dir, "n1", 1, "x" * 400) # estimate 100 tokens, far over 50
      write_savepoint(dir, [transition(stamp("2026-01-01T09:00:00Z"), "n1", "running",
                                        fields: RUNNING.merge(input: sha))])

      record = GraphMeasureBudget.read(dir)
      attempt = record[:nodes]["n1"][:attempts].first
      assert_equal true, attempt[:over_budget]
    end
  end

  # --- 4.11: a missing packet file is unavailable, with its sha (D18) -----------

  def test_missing_packet_file_is_unavailable_with_its_sha
    with_intent_dir do |dir|
      write_node_file(dir, "n1", "work", budget: 120_000)
      missing_sha = "deadbeef0000"
      write_savepoint(dir, [transition(stamp("2026-01-01T09:00:00Z"), "n1", "running",
                                        fields: RUNNING.merge(input: missing_sha))])

      record = GraphMeasureBudget.read(dir)
      attempt = record[:nodes]["n1"][:attempts].first
      refute attempt[:file_exists]
      assert_equal :unavailable, attempt[:bytes]
      assert_equal :unavailable, attempt[:estimate_tokens]
      assert_equal :unavailable, attempt[:effective_tokens]
      assert_equal missing_sha, attempt[:packet_sha_declared]
    end
  end
end
