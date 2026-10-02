# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "open3"
require "rbconfig"
require "tmpdir"
require "time"
require_relative "../scripts/lib/plastic"
require_relative "../scripts/lib/plastic/graph/evidence_writer"

module Plastic
  # Generates public benchmark input and records whole-process command timings.
  module RetrievalBenchmark
    ROOT = File.expand_path("..", __dir__)
    SCHEMA_PATH = File.join(__dir__, "retrieval_benchmark_schema.json")
    TEXT = "Plastic retrieval benchmark prose: common context terms and a rare marker. Živjeli.\n"
    DOCUMENT_BYTES = 4_096

    module_function

    def schema = JSON.parse(File.read(SCHEMA_PATH))

    def generate_corpus(directory, target_bytes:, stores: 3)
      FileUtils.mkdir_p(directory)
      corpus_receipt(corpus_paths(directory, target_bytes, stores))
    end

    def run(output:, corpus_bytes: 15_000_000, warmup: schema.dig("warmup_samples", "warmup"), samples: schema.dig("warmup_samples", "samples"), quality_input: nil)
      Dir.mktmpdir("plastic-retrieval-benchmark") do |directory|
        corpus = generate_corpus(File.join(directory, "corpus"), target_bytes: corpus_bytes, stores: 3)
        benchmark = seed_benchmark_home(directory, corpus)
        commands = benchmark_commands(benchmark, warmup, samples)
        report = report_for(corpus, commands, warmup, samples).merge("commands" => benchmark.fetch("commands"))
        report["quality"] = evaluate_quality(quality_input, directory) if quality_input
        FileUtils.mkdir_p(File.dirname(File.expand_path(output)))
        File.write(output, JSON.pretty_generate(report) + "\n")
        report
      end
    end

    def benchmark_commands(benchmark, warmup, samples)
      benchmark.fetch("commands").to_h do |id, command|
        warmup.times { run_command(command) }
        [id, samples.times.map { run_command(command) }]
      end
    end

    def run_command(command)
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      environment = { "RUBYOPT" => "", "PLASTIC_HOME" => command.fetch(:home) }
      stdout, stderr, status = Open3.capture3(environment, *command.fetch(:argv))
      { "started_at" => Time.now.utc.iso8601, "duration_ms" => ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round(3),
        "exit_status" => status.exitstatus, "argv" => command.fetch(:argv), "stdout" => stdout, "stderr" => stderr,
        "stdout_sha256" => Digest::SHA256.hexdigest(stdout), "stderr_sha256" => Digest::SHA256.hexdigest(stderr) }
    end

    def report_for(corpus, commands, warmup, samples)
      { "schema_version" => schema.fetch("schema_version"), "generated_at" => Time.now.utc.iso8601,
        "hardware" => { "ruby" => RUBY_DESCRIPTION, "platform" => RUBY_PLATFORM, "cpu" => `sysctl -n machdep.cpu.brand_string 2>/dev/null`.strip, "memory_bytes" => `sysctl -n hw.memsize 2>/dev/null`.strip },
        "cache" => schema.dig("warmup_samples", "cache"), "warmup" => warmup, "samples" => samples, "corpus" => corpus,
        "targets_ms" => schema.fetch("warm_p95_targets_ms"), "measurements" => commands,
        "owner_review" => { "status" => "pending", "reason" => "Synthetic corpus measurements do not satisfy the owner-reviewed quality gate." } }
    end

    def write_store(directory, index, size)
      store = File.join(directory, "store-#{index + 1}")
      FileUtils.mkdir_p(store)
      document_sizes(size).each_with_index.map do |document_size, document_index|
        path = File.join(store, format("document-%05d.md", document_index + 1))
        File.write(path, public_text(document_size, index, document_index), encoding: "UTF-8")
        path
      end
    end

    def corpus_paths(directory, target_bytes, stores)
      stores.times.flat_map { |index| write_store(directory, index, bytes_for_store(index, target_bytes, stores)) }
    end

    def bytes_for_store(index, target_bytes, stores)
      target_bytes / stores + ((index < target_bytes % stores) ? 1 : 0)
    end

    def corpus_receipt(paths)
      { "bytes" => paths.sum { |path| File.size(path) }, "documents" => paths.length,
        "stores" => paths.map { |path| File.basename(File.dirname(path)) }.uniq, "files" => paths,
        "sha256" => Digest::SHA256.hexdigest(paths.map { |path| File.binread(path) }.join) }
    end

    def document_sizes(size)
      Array.new(size / DOCUMENT_BYTES, DOCUMENT_BYTES).tap { |sizes| sizes << size % DOCUMENT_BYTES unless (size % DOCUMENT_BYTES).zero? }
    end

    def public_text(size, store_index, document_index)
      prefix = "store#{store_index + 1} document#{document_index + 1} common retrieval evidence rare-store-#{store_index + 1}. Živjeli.\n"
      prefix + ("public benchmark text \n" * ((size - prefix.bytesize) / 22 + 1)).byteslice(0, [size - prefix.bytesize, 0].max).to_s
    end

    def seed_benchmark_home(directory, corpus)
      home = File.join(directory, "home")
      stores = corpus.fetch("files").group_by { |path| File.basename(File.dirname(path)) }
      stores.each { |store, paths| seed_store(home, store, paths) }
      reference = Graph.open(home:, store: stores.keys.first).retrieval.reference("1", File.basename(stores.values.first.first))
      { "commands" => commands_for(home, reference), "reference" => reference }
    end

    def seed_store(home, store, paths)
      graphs = Graph.open(home:, store:)
      graphs.databases.each_value { |database| database.rows("SELECT 1") }
      writer = Graph::EvidenceWriter.new(graphs.databases.fetch(:knowledge), graphs.retrieval.origin_id)
      paths.each_with_index { |path, index| writer.write((index + 1).to_s, File.basename(path), File.read(path, encoding: "UTF-8")) }
      graphs.retrieval.backfill!
    end

    def commands_for(home, reference)
      executable = [RbConfig.ruby, File.join(ROOT, "bin", "plastic")]
      stores = %w[store-1 store-2 store-3]
      { "exact_lookup" => { home:, argv: [*executable, "document", "get", reference.fetch(:uri), "--json"] },
        "single_store_top_20" => { home:, argv: [*executable, "search", "common", "--source-project", stores.first, "--limit", "20", "--json"] },
        "three_store_rrf_top_20" => { home:, argv: [*executable, "search", "common", *stores.flat_map { |store| ["--source-project", store] }, "--limit", "20", "--json"] } }
    end

    def evaluate_quality(input, directory)
      candidate = JSON.parse(File.read(input))
      home = File.join(directory, "quality-home")
      documents = candidate.fetch("documents")
      documents.group_by { |document| document.fetch("store") }.each do |store, rows|
        graphs = Graph.open(home:, store:)
        graphs.databases.each_value { |database| database.rows("SELECT 1") }
        writer = Graph::EvidenceWriter.new(graphs.databases.fetch(:knowledge), graphs.retrieval.origin_id)
        rows.each { |row| writer.write(row.fetch("intent_id"), row.fetch("path"), row.fetch("content")) }
        graphs.retrieval.backfill!
      end
      answers = candidate.fetch("queries").map { |query| evaluate_query(query, home) }
      { "status" => candidate.fetch("status"), "owner_review" => { "status" => "pending" }, "synthetic_top_20" => answers,
        "synthetic_recall" => answers.count { |answer| answer.fetch("passed") }.fdiv(answers.length) }
    end

    def evaluate_query(query, home)
      expected = query.fetch("expected").map do |row|
        Graph.open(home:, store: row.fetch("store")).retrieval.reference(row.fetch("intent_id"), row.fetch("path")).fetch(:uri)
      end
      hits = query.fetch("scope").flat_map do |store|
        Graph.open(home:, store:).retrieval.search(query.fetch("harness_search_terms"), limit: 20).map do |row|
          Graph.open(home:, store:).retrieval.search_reference(row).fetch(:uri)
        end
      end
      { "id" => query.fetch("id"), "expected_references" => expected, "returned_references" => hits, "passed" => (expected & hits).any? }
    end
  end
end
