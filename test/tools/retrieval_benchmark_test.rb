# frozen_string_literal: true

require_relative "../test_helper"
require "json"
require "open3"
require_relative "../../tools/retrieval_benchmark"

class RetrievalBenchmarkTest < Minitest::Test
  def test_declares_reproducible_public_corpora_and_full_cli_measurements
    schema = Plastic::RetrievalBenchmark.schema

    assert_equal expected_schema, schema_summary(schema)
  end

  def test_generates_deterministic_utf8_text_without_binary_padding
    Dir.mktmpdir do |directory|
      first = Plastic::RetrievalBenchmark.generate_corpus(directory, target_bytes: 20_000, stores: 3)
      second = Plastic::RetrievalBenchmark.generate_corpus(File.join(directory, "again"), target_bytes: 20_000, stores: 3)

      assert_equal corpus_summary(first), corpus_summary(second)
    end
  end

  def test_worker_does_not_execute_when_a_quality_gate_requires_its_source
    Dir.mktmpdir do |directory|
      worker = File.expand_path("../../tools/retrieval_benchmark/worker.rb", __dir__)
      source = File.expand_path("../../scripts/lib/plastic.rb", __dir__)
      stdout, stderr, status = Open3.capture3(RbConfig.ruby, "-e", "require ARGV.fetch(0)", worker, source, chdir: directory)

      assert_equal [true, "", "", []], [status.success?, stdout, stderr, Dir.children(directory)]
    end
  end

  def test_writes_raw_evidence_to_a_new_output_directory
    Dir.mktmpdir do |directory|
      output = File.join(directory, "evidence", "benchmark.json")

      report = Plastic::RetrievalBenchmark.run(output:, corpus_bytes: 1_000, warmup: 0, samples: 1)

      assert_equal({ owner_review: "pending", commands_succeeded: true, no_help: true }, raw_evidence_summary(output, report))
    end
  end

  def test_records_concurrent_reads_and_explicit_acceptance_gates
    Dir.mktmpdir do |directory|
      report = Plastic::RetrievalBenchmark.run(output: File.join(directory, "benchmark.json"), corpus_bytes: 20_000, warmup: 0, samples: 1)

      concurrent = report.fetch("measurements").fetch("concurrent_writer_reader")

      assert_equal({ busy: "no_busy_errors", immutable: true, owner_review: "pending", p95: %w[exact_lookup single_store_top_20 three_store_rrf_top_20], writer_stderr: "", overlap: true }, concurrency_summary(report, concurrent))
    end
  end

  def test_scores_the_public_fixture_with_a_ranked_answer_bearing_passage
    Dir.mktmpdir do |directory|
      report = Plastic::RetrievalBenchmark.run(output: File.join(directory, "benchmark.json"), corpus_bytes: 20_000, warmup: 0, samples: 1,
        quality_input: File.expand_path("../../resources/retrieval-quality-review.json", __dir__))
      answer = report.fetch("quality").fetch("synthetic_top_20").fetch(0)

      assert_equal({ owner_review: "pending", passed: true, rank: 1, answer_bearing: true }, quality_summary(report, answer))
    end
  end

  def test_checks_the_ranked_passage_instead_of_the_search_excerpt
    Dir.mktmpdir do |directory|
      report = Plastic::RetrievalBenchmark.run(output: File.join(directory, "benchmark.json"), corpus_bytes: 20_000, warmup: 0, samples: 1,
        quality_input: File.expand_path("../../resources/retrieval-quality-review.json", __dir__))
      answers = report.fetch("quality").fetch("synthetic_top_20")

      assert_equal [true], answers.map { |answer| answer.fetch("passage_checks").first.fetch("matched") }
    end
  end

  private

  def timed_samples(report)
    report.fetch("measurements").slice("exact_lookup", "single_store_top_20", "three_store_rrf_top_20").values.flatten
  end

  def expected_schema
    { "schema_version" => 1, "entrypoint" => "bin/plastic", "corpora" => [15_000_000, 100_000_000], "public_text" => true,
      "measurements" => %w[exact_lookup single_store_top_20 three_store_rrf_top_20 concurrent_writer_reader],
      "targets" => { "exact_lookup" => 100, "single_store_top_20" => 250, "three_store_rrf_top_20" => 500 } }
  end

  def schema_summary(schema)
    { "schema_version" => schema.fetch("schema_version"), "entrypoint" => schema.fetch("entrypoint"),
      "corpora" => schema.fetch("corpora").map { |corpus| corpus.fetch("target_bytes") },
      "public_text" => schema.fetch("corpora").all? { |corpus| corpus.fetch("text_encoding") == "UTF-8" && corpus.fetch("public_data") },
      "measurements" => schema.fetch("measurements").map { |measurement| measurement.fetch("id") }, "targets" => schema.fetch("warm_p95_targets_ms") }
  end

  def corpus_summary(corpus)
    { bytes: corpus.fetch("bytes"), sha256: corpus.fetch("sha256"), stores: corpus.fetch("stores").length,
      valid_utf8: corpus.fetch("files").all? { |path| File.read(path, encoding: "UTF-8").valid_encoding? } }
  end

  def raw_evidence_summary(output, report)
    { owner_review: JSON.parse(File.read(output)).dig("owner_review", "status"), commands_succeeded: timed_samples(report).all? { |sample| sample.fetch("exit_status").zero? },
      no_help: timed_samples(report).none? { |sample| sample.fetch("argv").include?("--help") } }
  end

  def concurrency_summary(report, concurrent)
    { busy: concurrent.fetch("busy_handling").fetch("status"), immutable: concurrent.fetch("reader_samples").all? { |sample| sample.fetch("immutable_reference_consistent") },
      owner_review: report.fetch("acceptance_gates").fetch("owner_review").fetch("status"), p95: report.fetch("p95_ms").keys,
      writer_stderr: concurrent.fetch("writer_stderr"), overlap: concurrent.fetch("overlap") }
  end

  def quality_summary(report, answer)
    { owner_review: report.fetch("quality").dig("owner_review", "status"), passed: answer.fetch("passed"), rank: answer.fetch("rank"),
      answer_bearing: answer.fetch("matched_text").include?("immutable revisions retain history") }
  end
end
