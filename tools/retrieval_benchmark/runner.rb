# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "open3"
require "rbconfig"
require "tmpdir"
require "time"
require_relative "../../scripts/lib/plastic"
require_relative "../../scripts/lib/plastic/graph/evidence_writer"
require_relative "concurrency"

module Plastic
  module RetrievalBenchmark
    class Runner
      def initialize(output:, corpus_bytes:, warmup:, samples:, quality_input:)
        @output = output
        @corpus_bytes = corpus_bytes
        @warmup = warmup
        @samples = samples
        @quality_input = quality_input
      end

      def run
        Dir.mktmpdir("plastic-retrieval-benchmark") do |directory|
          corpus = RetrievalBenchmark.generate_corpus(File.join(directory, "corpus"), target_bytes: @corpus_bytes)
          benchmark = Seeder.new(directory, corpus).seed
          measurements = Measurements.new(benchmark, @warmup, @samples).measure
          report = Report.new(corpus, measurements, @warmup, @samples).build
          report["quality"] = QualityEvaluator.new(@quality_input, directory).evaluate if @quality_input
          write_report(report)
          report
        end
      end

      private

      def write_report(report)
        FileUtils.mkdir_p(File.dirname(File.expand_path(@output)))
        File.write(@output, JSON.pretty_generate(report) + "\n")
      end
    end

    class Seeder
      def initialize(directory, corpus)
        @home = File.join(directory, "home")
        @corpus = corpus
      end

      def seed
        stores.each { |store, paths| seed_store(store, paths) }
        reference = Graph.open(home: @home, store: stores.keys.first).retrieval.reference("1", File.basename(stores.values.first.first))
        { home: @home, reference:, commands: commands(reference) }
      end

      private

      def stores = @corpus.fetch("files").group_by { |path| File.basename(File.dirname(path)) }

      def seed_store(store, paths)
        graphs = Graph.open(home: @home, store:)
        initialize_databases(graphs)
        write_paths(graphs, paths)
        graphs.retrieval.backfill!
      end

      def initialize_databases(graphs) = graphs.databases.each_value { |database| database.rows("SELECT 1") }

      def write_paths(graphs, paths)
        writer = Graph::EvidenceWriter.new(graphs.databases.fetch(:knowledge), graphs.retrieval.origin_id)
        paths.each_with_index { |path, index| writer.write((index + 1).to_s, File.basename(path), File.read(path, encoding: "UTF-8")) }
      end

      def commands(reference)
        executable = [RbConfig.ruby, File.join(RetrievalBenchmark::ROOT, "bin", "plastic")]
        stores = %w[store-1 store-2 store-3]
        { "exact_lookup" => command([*executable, "document", "get", reference.fetch(:uri), "--json"], reference:),
          "single_store_top_20" => command([*executable, "search", "common", "--source-project", stores.first, "--limit", "20", "--json"], stores: [stores.first]),
          "three_store_rrf_top_20" => command([*executable, "search", "common", *stores.flat_map { |store| ["--source-project", store] }, "--limit", "20", "--json"], stores:) }
      end

      def command(argv, reference: nil, stores: nil) = { home: @home, argv:, reference:, stores: }.compact
    end

    class Measurements
      def initialize(benchmark, warmup, samples)
        @benchmark = benchmark
        @warmup = warmup
        @samples = samples
      end

      def measure
        timed = @benchmark.fetch(:commands).to_h { |id, command| [id, timed_samples(command)] }
        timed.merge("concurrent_writer_reader" => Concurrency.new(@benchmark, @samples).measure)
      end

      def self.run_command(command)
        started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        stdout, stderr, status = Open3.capture3(environment(command), *command.fetch(:argv))
        sample(command, stdout, stderr, status, started)
      end

      def self.environment(command)
        home = command.fetch(:home)
        { "HOME" => home, "PLASTIC_HOME" => home, "PLASTIC_TMP" => File.join(home, "tmp"), "PLASTIC_SOURCE_PROJECTS" => "", "RUBYOPT" => "" }
      end

      def self.sample(command, stdout, stderr, status, started)
        { "started_at" => Time.now.utc.iso8601, "duration_ms" => elapsed_ms(started), "exit_status" => status.exitstatus,
          "argv" => command.fetch(:argv), "stdout" => stdout, "stderr" => stderr,
          "stdout_sha256" => Digest::SHA256.hexdigest(stdout), "stderr_sha256" => Digest::SHA256.hexdigest(stderr),
          "output_valid" => OutputValidator.valid?(command, stdout, status) }
      end

      def self.elapsed_ms(started) = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round(3)

      private

      def timed_samples(command)
        @warmup.times { self.class.run_command(command) }
        @samples.times.map { self.class.run_command(command) }
      end
    end

    class OutputValidator
      def self.valid?(command, stdout, status)
        return false unless status.success?

        result = JSON.parse(stdout).fetch("result")
        return exact_match?(command, result) if command[:reference]

        selected_store_match?(command, result)
      rescue JSON::ParserError, KeyError
        false
      end

      def self.exact_match?(command, result) = result.fetch("document").fetch("uri") == command.fetch(:reference).fetch(:uri)

      def self.selected_store_match?(command, result)
        returned = result.fetch("results").map { |row| row.fetch("store") }.uniq
        returned.any? && (returned - command.fetch(:stores)).empty?
      end
    end

    class Report
      def initialize(corpus, measurements, warmup, samples)
        @corpus = corpus
        @measurements = measurements
        @warmup = warmup
        @samples = samples
      end

      def build
        p95 = p95_measurements
        { "schema_version" => RetrievalBenchmark.schema.fetch("schema_version"), "generated_at" => Time.now.utc.iso8601,
          "hardware" => hardware, "cache" => RetrievalBenchmark.schema.dig("warmup_samples", "cache"), "warmup" => @warmup, "samples" => @samples,
          "corpus" => @corpus, "targets_ms" => targets, "measurements" => @measurements, "p95_ms" => p95,
          "acceptance_gates" => acceptance_gates(p95),
          "owner_review" => { "status" => "pending", "reason" => "Synthetic corpus measurements do not satisfy the owner-reviewed quality gate." } }
      end

      private

      def hardware
        { "ruby" => RUBY_DESCRIPTION, "platform" => RUBY_PLATFORM,
          "cpu" => `sysctl -n machdep.cpu.brand_string 2>/dev/null`.strip,
          "memory_bytes" => `sysctl -n hw.memsize 2>/dev/null`.strip }
      end

      def targets = RetrievalBenchmark.schema.fetch("warm_p95_targets_ms")

      def p95_measurements
        @measurements.slice("exact_lookup", "single_store_top_20", "three_store_rrf_top_20").transform_values do |samples|
          samples.map { |sample| sample.fetch("duration_ms") }.sort.fetch((samples.length * 0.95).ceil - 1)
        end
      end

      def acceptance_gates(p95)
        latency = p95.to_h do |id, duration|
          [id, { "status" => (duration <= targets.fetch(id)) ? "passed" : "missed", "p95_ms" => duration, "target_ms" => targets.fetch(id) }]
        end
        { "latency" => latency, "owner_review" => { "status" => "pending" }, "intent_ready" => false }
      end
    end
  end
end
