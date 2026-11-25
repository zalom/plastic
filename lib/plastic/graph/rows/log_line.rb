# frozen_string_literal: true

require "json"
require_relative "../../clock"
require_relative "../record"

module Plastic
  module Graph
    module Work
      # One line of an intent's work.log: when it happened, in which phase and on which node,
      # which session wrote it, what kind of event it was, and the path and the full hash
      # of the document it wrote. An empty field prints as a dash. An amended change to the text inside a file also holds
      # the exact old and new text, printed as two quoted fields after the hash. A line that does not parse reads back as a
      # `noted` line that keeps its words.
      LogLine = Data.define(:intent_id, :position, :at, :phase, :node, :session_id, :kind, :path, :sha256, :text, :origin_id, :old_text, :new_text) do
        def initialize(old_text: nil, new_text: nil, **fields) = super
      end

      # How a line prints and reads.
      class LogLine
        include Record

        EMPTY = "-"
        HASH_PREFIX = "sha256:"
        QUOTED = /"(?:[^"\\]|\\.)*"/
        TEXT_CHANGE = / old=(?<old_text>#{QUOTED}) new=(?<new_text>#{QUOTED})/
        FORM = /\A- (?<at>\d{4}-\d\d-\d\dT\S+|-) (?<phase>\S+) (?<node>\S+) (?<session_id>\S+) (?<kind>[a-z_]+) (?<path>\S+) (?<sha256>sha256:\h{64}|-)(?:#{TEXT_CHANGE})?(?: (?<text>.*))?\z/

        # The fields one printed line holds; a line that does not parse is a `noted` line of its own words.
        def self.parse(line)
          found = line.match(FORM)
          found ? parsed(found) : { at: nil, phase: "", node: "", session_id: nil, kind: "noted", path: "", sha256: "", text: line.strip }
        end

        def self.parsed(found)
          fields = found.named_captures.transform_keys(&:to_sym)
          fields.except(:old_text, :new_text).merge(at: Plastic.utc(unset(fields[:at])), session_id: unset(fields[:session_id]), sha256: bare(fields[:sha256]),
            text: fields[:text].to_s, **words(fields), **text_change(fields))
        end

        # The phase, the node and the path a line names, each empty for a dash.
        def self.words(fields) = fields.slice(:phase, :node, :path).transform_values { |word| blank(word) }

        # The old and the new text a line quotes, or nothing when it quotes none.
        def self.text_change(fields) = fields.slice(:old_text, :new_text).compact.transform_values { |quoted| JSON.parse(quoted) }

        def self.bare(word) = word.delete_prefix(HASH_PREFIX).delete_prefix(EMPTY)

        def self.unset(word) = (word == EMPTY) ? nil : word

        def self.blank(word) = (word == EMPTY) ? "" : word

        def values_at(*keys) = to_h.values_at(*keys)

        def self.word(value)
          text = value.to_s
          text.empty? ? EMPTY : text.gsub(/\s+/, "_")
        end

        def self.one_line(value) = value.to_s.gsub(/\s*\R\s*/, " ").strip

        def line
          form = self.class
          head = [at, phase, node, session_id].map { |value| form.word(value) }
          ["-", *head, kind, form.word(path), hash_word, *text_change, form.one_line(text)].reject(&:empty?).join(" ")
        end

        # The line as a person reads it: its time in `zone` or else the zone of the machine. `line` stays the work.log form.
        def shown(zone = nil) = with(at: Plastic.local(at, zone)).line

        private

        def hash_word = sha256.to_s.empty? ? EMPTY : "#{HASH_PREFIX}#{sha256}"

        # The old and the new text of a change to the text inside a file, quoted, or nothing for any other line.
        def text_change = (old_text.nil? && new_text.nil?) ? [] : ["old=#{JSON.generate(old_text.to_s)}", "new=#{JSON.generate(new_text.to_s)}"]
      end
    end
  end
end
