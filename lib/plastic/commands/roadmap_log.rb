# frozen_string_literal: true

require_relative "../routine"

module Plastic
  module Commands
    # Appends a log line to a roadmap, stamped with the session id.
    class RoadmapLog < Routine
      subject :slug
      argument :slug, label: "SLUG", text: "the roadmap"
      argument :text, label: "TEXT", text: "the log line", rest: true
      writes :work
      prints :roadmap

      workflow :code_log_roadmap, next: :noop
    end
  end
end
