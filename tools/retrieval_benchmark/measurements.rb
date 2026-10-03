# frozen_string_literal: true

require "digest"
require "open3"
require "time"
require_relative "concurrency"
require_relative "output_validator"

module Plastic
  module RetrievalBenchmark
    # Captures spawned CLI measurements and their raw output evidence.
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
        started_at = Time.now.utc.iso8601(6)
        stdout, stderr, status = Open3.capture3(environment(command), *command.fetch(:argv))
        sample(command, { stdout:, stderr:, status:, started:, started_at: })
      end

      def self.environment(command)
        home = command.fetch(:home)
        { "HOME" => home, "PLASTIC_HOME" => home, "PLASTIC_TMP" => File.join(home, "tmp"), "PLASTIC_SOURCE_PROJECTS" => "", "RUBYOPT" => "" }
      end

      def self.sample(command, result)
        stdout, stderr, status = result.values_at(:stdout, :stderr, :status)
        { "started_at" => result.fetch(:started_at), "duration_ms" => elapsed_ms(result.fetch(:started)), "exit_status" => status.exitstatus,
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
  end
end
