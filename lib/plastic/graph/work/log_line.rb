# frozen_string_literal: true

require_relative "../record"

module Plastic
  module Graph
    module Work
      # One line of an intent's work.log: when it happened, in which phase and on which node,
      # which session wrote it, what kind of event it was, and the path and the full hash
      # of the document it wrote. An empty field prints as a dash. A line that does not
      # parse reads back as a `noted` line that keeps its words.
      LogLine = Data.define(:intent_id, :position, :at, :phase, :node, :session_id, :kind, :path, :sha256, :text, :origin_id)

      # How a line prints and reads.
      class LogLine
        include Record

        EMPTY = "-"
        HASH_PREFIX = "sha256:"
        FORM = /\A- (?<at>\d{4}-\d\d-\d\dT\S+|-) (?<phase>\S+) (?<node>\S+) (?<session_id>\S+) (?<kind>[a-z_]+) (?<path>\S+) (?<sha256>sha256:\h{64}|-)(?: (?<text>.*))?\z/

        # The fields one printed line holds; a line that does not parse is a `noted` line of its own words.
        def self.parse(line)
          found = line.match(FORM)
          found ? parsed(found) : { at: nil, phase: "", node: "", session_id: nil, kind: "noted", path: "", sha256: "", text: line.strip }
        end

        def self.parsed(found)
          fields = found.named_captures.transform_keys(&:to_sym)
          fields.merge(at: unset(fields[:at]), phase: blank(fields[:phase]), node: blank(fields[:node]), session_id: unset(fields[:session_id]),
            path: blank(fields[:path]), sha256: fields[:sha256].delete_prefix(HASH_PREFIX).delete_prefix(EMPTY), text: fields[:text].to_s)
        end

        def self.unset(word) = (word == EMPTY) ? nil : word

        def self.blank(word) = (word == EMPTY) ? "" : word

        def values_at(*keys) = to_h.values_at(*keys)

        def line = ["-", word(at), word(phase), word(node), word(session_id), kind, word(path), hash_word, one_line(text)].reject(&:empty?).join(" ")

        private

        def word(value) = value.to_s.empty? ? EMPTY : value.to_s.gsub(/\s+/, "_")

        def hash_word = sha256.to_s.empty? ? EMPTY : "#{HASH_PREFIX}#{sha256}"

        def one_line(value) = value.to_s.gsub(/\s*\R\s*/, " ").strip
      end
    end
  end
end
