# frozen_string_literal: true

module CommandReference
  module Markdown
    # The README that lists every command, in groups.
    class Index
      CORE = %w[install update rollback uninstall version doctor status next search auto].freeze
      FAMILIES = %w[intent project sync session backup document architecture node edge graph roadmap hook].freeze

      def initialize(pages)
        @pages = pages
      end

      def to_s
        ["# Command reference", "", INTRO, "", *groups.flat_map { |title, pages| Index.section(title, pages) }].join("\n")
      end

      INTRO = "Each page explains one plastic command: what it takes, what it touches, the workflows it runs, where each workflow stops, and how it ends. " \
        "A script writes every page from the command classes, so a page always matches the code it links to. " \
        "Every command is declared in the same small DSL, shown in [the command DSL](../dsl/README.md)."

      def self.group(words)
        first = words.split.first
        (CORE.include?(words) || !FAMILIES.include?(first)) ? "Core" : first
      end

      def self.section(title, pages)
        ["## #{title}", "", "| Command | What it does |", "| --- | --- |",
          *pages.map { |page| "| [`plastic #{page.words}`](#{page.slug}/README.md) | #{page.summary} |" }, ""]
      end

      private

      def groups
        titles = ["Core", *FAMILIES]
        @pages.group_by { |page| Index.group(page.words) }.sort_by { |title, _| titles.index(title) }
      end
    end
  end
end
