# encoding: UTF-8

require "timeout"
require_relative "../read_config"
require_relative "../active_delivery"
require_relative "../runner_core"
require_relative "../runner_watch"

module SessionStartHook
  # One unrecorded tick (record: false: reclaim and classify, no snapshot, no
  # record line) per intent ActiveDelivery.candidate_intent_dirs finds,
  # naming every stalled or done_unreported one in a single line (intent
  # 340a, G7b, n3, graph.md D10). A raise or a hang on any one candidate must
  # add nothing, never a partial line.
  module DeliveryWatch
    def self.line(plastic_home:, store_dir:)
      Timeout.timeout(2) { build_line(plastic_home, store_dir) }
    rescue Exception # rubocop:disable Lint/RescueException -- any failure or timeout stays silent, never crashes boot
      nil
    end

    def self.build_line(plastic_home, store_dir)
      attention = candidates(store_dir, resolve_project_roots(plastic_home))
      attention.any? ? "PLASTIC watch: #{attention.join(", ")}" : nil
    end

    def self.resolve_project_roots(plastic_home)
      roots = ReadConfig.resolve("project_roots", ReadConfig::Options.new(plastic_home: plastic_home))
      Array(roots).map { |root| File.expand_path(root.to_s) }
    end

    def self.candidates(store_dir, project_roots)
      ActiveDelivery.candidate_intent_dirs(global_store: store_dir, project_roots: project_roots)
        .uniq.filter_map { |dir| line_for(dir) }
    end

    def self.line_for(dir)
      result = RunnerWatch.tick(RunnerCore.context(intent_dir: dir), record: false)
      state = result[:class]
      return unless %w[stalled done_unreported].include?(state)

      describe_attention(dir, state, result)
    end

    ATTENTION_LINES = {
      "stalled" => ->(intent_id, result) { stalled_line(intent_id, result) },
      "done_unreported" => ->(intent_id, _result) { "#{intent_id} done_unreported" }
    }.freeze

    def self.describe_attention(dir, state, result)
      intent_id = File.basename(dir).split("--").first
      ATTENTION_LINES.fetch(state).call(intent_id, result)
    end

    def self.stalled_line(intent_id, result)
      blocker = Array(result[:blockers]).first
      blocker ? "#{intent_id} stalled (#{blocker})" : "#{intent_id} stalled"
    end
  end
end
