# frozen_string_literal: true

require_relative "../test_helper"
require "json"
require_relative "../../tools/retrieval_benchmark"

class RetrievalBenchmarkTest < Minitest::Test
  def test_declares_reproducible_public_corpora_and_full_cli_measurements
    schema = Plastic::RetrievalBenchmark.schema

    assert_equal 1, schema.fetch("schema_version")
    assert_equal "bin/plastic", schema.fetch("entrypoint")
    assert_equal [15_000_000, 100_000_000], schema.fetch("corpora").map { |corpus| corpus.fetch("target_bytes") }
    assert schema.fetch("corpora").all? { |corpus| corpus.fetch("text_encoding") == "UTF-8" && corpus.fetch("public_data") }
    assert_equal %w[exact_lookup single_store_top_20 three_store_rrf_top_20 concurrent_writer_reader], schema.fetch("measurements").map { |measurement| measurement.fetch("id") }
    assert_equal({ "exact_lookup" => 100, "single_store_top_20" => 250, "three_store_rrf_top_20" => 500 }, schema.fetch("warm_p95_targets_ms"))
  end

  def test_generates_deterministic_utf8_text_without_binary_padding
    Dir.mktmpdir do |directory|
      first = Plastic::RetrievalBenchmark.generate_corpus(directory, target_bytes: 20_000, stores: 3)
      second = Plastic::RetrievalBenchmark.generate_corpus(File.join(directory, "again"), target_bytes: 20_000, stores: 3)

      assert_equal first.fetch("bytes"), second.fetch("bytes")
      assert_equal first.fetch("sha256"), second.fetch("sha256")
      assert_equal 3, first.fetch("stores").length
      assert first.fetch("files").all? { |path| File.read(path, encoding: "UTF-8").valid_encoding? }
    end
  end

  def test_writes_raw_evidence_to_a_new_output_directory
    Dir.mktmpdir do |directory|
      output = File.join(directory, "evidence", "benchmark.json")

      report = Plastic::RetrievalBenchmark.run(output:, corpus_bytes: 1_000, warmup: 0, samples: 1)

      assert_equal "pending", JSON.parse(File.read(output)).dig("owner_review", "status")
      assert report.fetch("measurements").values.flatten.all? { |sample| sample.fetch("exit_status").zero? }
      refute report.fetch("measurements").values.flatten.any? { |sample| sample.fetch("argv").include?("--help") }
    end
  end

  def test_records_concurrent_reads_and_explicit_acceptance_gates
    Dir.mktmpdir do |directory|
      report = Plastic::RetrievalBenchmark.run(output: File.join(directory, "benchmark.json"), corpus_bytes: 20_000, warmup: 0, samples: 1)

      concurrent = report.fetch("measurements").fetch("concurrent_writer_reader")
      assert_equal "no_busy_errors", concurrent.fetch("busy_handling").fetch("status")
      assert concurrent.fetch("reader_samples").all? { |sample| sample.fetch("immutable_reference_consistent") }
      assert_equal "pending", report.fetch("acceptance_gates").fetch("owner_review").fetch("status")
      assert_equal %w[exact_lookup single_store_top_20 three_store_rrf_top_20], report.fetch("p95_ms").keys
    end
  end
end
