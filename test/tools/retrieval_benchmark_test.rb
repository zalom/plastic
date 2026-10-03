# frozen_string_literal: true

require_relative "../test_helper"
require "json"
require "minitest/mock"
require "open3"
require "timeout"
require_relative "../../tools/retrieval_benchmark"
require_relative "../../tools/retrieval_benchmark/worker"

class RetrievalBenchmarkCorpusTest < Minitest::Test
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

  def test_generates_only_full_documents_when_a_store_size_has_no_remainder
    Dir.mktmpdir do |directory|
      corpus = Plastic::RetrievalBenchmark.generate_corpus(directory, target_bytes: 8_192, stores: 1)

      assert_equal [8_192, 2], corpus.values_at("bytes", "documents")
    end
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
end

class RetrievalBenchmarkWorkerTest < Minitest::Test
  def test_worker_does_not_execute_when_a_quality_gate_requires_its_source
    Dir.mktmpdir do |directory|
      worker = File.expand_path("../../tools/retrieval_benchmark/worker.rb", __dir__)
      source = File.expand_path("../../scripts/lib/plastic.rb", __dir__)
      stdout, stderr, status = Open3.capture3(RbConfig.ruby, "-e", "require ARGV.fetch(0)", worker, source, chdir: directory)

      assert_equal [true, "", "", []], [status.success?, stdout, stderr, Dir.children(directory)]
    end
  end

  def test_worker_waits_for_the_barrier_and_writes_bounded_revisions
    Dir.mktmpdir do |directory|
      ready = File.join(directory, "ready")
      start = File.join(directory, "start")
      writes = []
      worker, writer = waiting_worker(directory, ready, start, writes)

      output = run_waiting_worker(worker, writer, ready, start, writes)

      assert_equal [true, 10, ["42", "notes.md", "concurrent writer revision 0"], ["42", "notes.md", "concurrent writer revision 9"]],
        [File.exist?(ready), writes.length, writes.first, writes.last]
      assert_equal %w[finished_at started_at], JSON.parse(output).keys.sort
    end
  end

  def test_worker_entrypoint_runs_only_when_its_file_is_the_program
    Dir.mktmpdir do |directory|
      worker = File.expand_path("../../tools/retrieval_benchmark/worker.rb", __dir__)
      ready = File.join(directory, "ready")
      start = File.join(directory, "start")
      File.write(start, "start")
      output, error, status = Open3.capture3(RbConfig.ruby, worker, "writer", File.join(directory, "home"), "0", ready, start, "42", "notes.md")

      assert_equal [true, "", true, %w[finished_at started_at]], [File.exist?(ready), error, status.success?, JSON.parse(output).keys.sort]
    end
  end

  def test_worker_entrypoint_does_not_run_when_the_file_is_loaded_by_another_program
    calls = []
    arguments = %w[worker home 1 ready start 42 notes.md]

    Plastic::RetrievalBenchmark::Worker.stub(:new, ->(passed) {
      calls << passed
      entrypoint_runner(calls)
    }) do
      assert_nil Plastic::RetrievalBenchmark::Worker.run_entrypoint(arguments:, program_name: "caller", file_name: "worker")
      Plastic::RetrievalBenchmark::Worker.run_entrypoint(arguments:, program_name: "worker", file_name: "worker")

      assert_equal [arguments.drop(1), :run], calls
    end
  end

  def test_worker_writes_revisions_after_the_barrier_opens
    Dir.mktmpdir do |directory|
      home = File.join(directory, "home")
      ready = File.join(directory, "ready")
      start = File.join(directory, "start")
      File.write(start, "start")
      worker = Plastic::RetrievalBenchmark::Worker.new([home, "1", ready, start, "1", "notes.md"])

      capture_io { worker.run }
      document = Plastic::Graph.open(home:, store: "store-1").retrieval.fetch_reference("plastic://store-1/1/notes.md")

      assert_equal [true, "concurrent writer revision 9"], [File.exist?(ready), document.fetch(:body)]
    end
  end

  def waiting_worker(directory, ready, start, writes)
    writer = Object.new
    writer.define_singleton_method(:write) { |intent_id, path, body| writes << [intent_id, path, body] }
    graphs = Struct.new(:databases, :retrieval).new({ knowledge: Object.new }, Struct.new(:origin_id).new("origin"))
    worker = Plastic::RetrievalBenchmark::Worker.new([directory, "1", ready, start, "42", "notes.md"])
    worker.define_singleton_method(:graphs) { graphs }
    [worker, writer]
  end

  def run_waiting_worker(worker, writer, ready, start, writes)
    execution = Thread.new { capture_io { Plastic::Graph::EvidenceWriter.stub(:new, writer) { worker.run } }.first }
    Timeout.timeout(1) { sleep 0.005 until File.exist?(ready) }
    Timeout.timeout(1) { sleep 0.001 until execution.status == "sleep" }

    assert_equal [true, []], [execution.alive?, writes]
    File.write(start, "start")
    execution.value
  ensure
    finish_worker(execution, start)
  end

  def finish_worker(execution, start)
    File.write(start, "start") unless File.exist?(start)
    execution&.join(1)
    execution&.kill if execution&.alive?
  end

  def entrypoint_runner(calls)
    runner = Object.new
    runner.define_singleton_method(:run) { calls << :run }
    runner
  end
end

class RetrievalBenchmarkConcurrencyTest < Minitest::Test
  def test_concurrency_closes_writer_streams_after_a_successful_measurement
    stdin = StringIO.new
    stdout = StringIO.new(JSON.generate("started_at" => "2026-10-03T00:00:00.000000Z", "finished_at" => "2026-10-03T00:00:01.000000Z"))
    stderr = StringIO.new
    wait = benchmark_wait
    benchmark = benchmark_for_concurrency

    result = with_benchmark_writer(stdin:, stdout:, stderr:, wait:) do
      Plastic::RetrievalBenchmark::Concurrency.new(benchmark, 0).measure
    end

    assert_equal ["no_busy_errors", true, true, true], [result.dig("busy_handling", "status"), stdin.closed?, stdout.closed?, stderr.closed?]
  end

  def test_concurrency_reports_busy_reader_errors
    stdin = StringIO.new
    stdout = StringIO.new(JSON.generate("started_at" => "2026-10-03T00:00:00.000000Z", "finished_at" => "2026-10-03T00:00:01.000000Z"))
    stderr = StringIO.new
    wait = benchmark_wait

    result = with_benchmark_writer(stdin:, stdout:, stderr:, wait:) do
      Plastic::RetrievalBenchmark::Measurements.stub(:run_command, busy_reader) do
        Plastic::RetrievalBenchmark::Concurrency.new(benchmark_for_concurrency, 1).measure
      end
    end

    assert_equal [1, "busy_errors", true], [result.dig("busy_handling", "busy_failures"), result.dig("busy_handling", "status"), result.dig("reader_samples", 0, "immutable_reference_consistent")]
  end

  def test_concurrency_re_raises_writer_start_failures_after_cleaning_up_without_streams
    benchmark = benchmark_for_concurrency

    error = Open3.stub(:popen3, ->(*) { raise Errno::ENOENT, "writer unavailable" }) do
      assert_raises(Errno::ENOENT) { Plastic::RetrievalBenchmark::Concurrency.new(benchmark, 0).measure }
    end

    assert_match "writer unavailable", error.message
  end

  def benchmark_for_concurrency
    home = "/tmp/plastic-benchmark-home"
    command = { home:, argv: ["plastic", "document", "get"] }
    { home:, reference: { intent_id: "42", path: "notes.md" }, commands: { "exact_lookup" => command } }
  end

  def with_benchmark_writer(stdin:, stdout:, stderr:, wait:)
    Open3.stub(:popen3, ->(*arguments) {
      File.write(arguments.fetch(-4), "ready")
      [stdin, stdout, stderr, wait]
    }) { yield }
  end

  def benchmark_wait
    Struct.new(:status) { def value = status }.new(Struct.new(:exitstatus).new(0))
  end

  def busy_reader
    body = "immutable body"
    { "stdout" => JSON.generate("result" => { "document" => { "body" => body, "revision" => Digest::SHA256.hexdigest(body) } }),
      "stderr" => "database is locked", "output_valid" => true, "started_at" => "2026-10-03T00:00:00.500000Z" }
  end
end

class RetrievalBenchmarkReportTest < Minitest::Test
  def test_writes_raw_evidence_to_a_new_output_directory
    Dir.mktmpdir do |directory|
      output = File.join(directory, "evidence", "benchmark.json")

      report = Plastic::RetrievalBenchmark.run(output:, corpus_bytes: 1_000, warmup: 0, samples: 1)

      assert_equal({ owner_review: "pending", commands_succeeded: true, no_help: true }, raw_evidence_summary(output, report))
    end
  end

  def test_persists_a_partial_report_when_a_quality_fixture_is_invalid
    Dir.mktmpdir do |directory|
      input = File.join(directory, "invalid-quality.json")
      output = File.join(directory, "evidence", "benchmark.json")
      File.write(input, "{")

      report = Plastic::RetrievalBenchmark.run(output:, corpus_bytes: 1_000, warmup: 0, samples: 1, quality_input: input)

      assert_equal "error", report.dig("quality", "status")
      assert_equal report, JSON.parse(File.read(output))
    end
  end

  def test_marks_a_latency_gate_missed_when_its_warm_p95_exceeds_the_target
    measurements = { "exact_lookup" => [{ "duration_ms" => 101 }], "single_store_top_20" => [{ "duration_ms" => 1 }],
                     "three_store_rrf_top_20" => [{ "duration_ms" => 1 }] }
    report = Plastic::RetrievalBenchmark::Report.new({}, measurements, 0, 1).build

    assert_equal "missed", report.dig("acceptance_gates", "latency", "exact_lookup", "status")
  end

  def test_rejects_a_failed_timed_command_output
    _stdout, _stderr, status = Open3.capture3("false")

    refute Plastic::RetrievalBenchmark::OutputValidator.valid?({}, "", status)
  end

  def test_records_concurrent_reads_and_explicit_acceptance_gates
    Dir.mktmpdir do |directory|
      report = Plastic::RetrievalBenchmark.run(output: File.join(directory, "benchmark.json"), corpus_bytes: 20_000, warmup: 0, samples: 1)

      concurrent = report.fetch("measurements").fetch("concurrent_writer_reader")

      assert_equal({ busy: "no_busy_errors", immutable: true, owner_review: "pending", p95: %w[exact_lookup single_store_top_20 three_store_rrf_top_20], writer_stderr: "", overlap: true }, concurrency_summary(report, concurrent))
    end
  end

  def timed_samples(report)
    report.fetch("measurements").slice("exact_lookup", "single_store_top_20", "three_store_rrf_top_20").values.flatten
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
end

class RetrievalBenchmarkQualityTest < Minitest::Test
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

  def quality_summary(report, answer)
    { owner_review: report.fetch("quality").dig("owner_review", "status"), passed: answer.fetch("passed"), rank: answer.fetch("rank"),
      answer_bearing: answer.fetch("matched_text").include?("immutable revisions retain history") }
  end
end
