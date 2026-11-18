# frozen_string_literal: true

module CommandReference
  # Words cut into lines of a given width, and short names.
  module Words
    PLACEHOLDER = /\A%\{\w+\}\z/

    def self.blank?(text) = text.to_s.strip.empty?

    def self.placeholder?(text) = text.to_s.match?(PLACEHOLDER)

    def self.wrap(words, width)
      words.to_s.split.reduce([]) { |all, word| join(all, word, width) }.then { |lines| lines.empty? ? [+""] : lines }
    end

    def self.join(all, word, width)
      *head, last = all
      (last && last.size + word.size + 1 <= width) ? [*head, "#{last} #{word}"] : [*all, word]
    end

    # A text with its %{name} placeholders as uppercase NAME words and its line breaks as spaces.
    def self.plain(text) = placeholders(text).gsub(/\s*\n\s*/, " ")

    def self.placeholders(text) = text.to_s.gsub(/%\{(\w+)\}/) { Regexp.last_match(1).upcase }

    # A text with its %{name} placeholders as <name> words, a space after one that a letter follows.
    def self.angled(text)
      text.to_s.gsub(/%\{(\w+)\}([A-Za-z]?)/) do
        letter = Regexp.last_match(2)
        "<#{Regexp.last_match(1).tr("_", " ")}>#{" " unless letter.empty?}#{letter}"
      end
    end

    # A text as one sentence: capital first letter, closing full stop, no line breaks.
    def self.sentence(text)
      one = angled(text).gsub(/\s*\n\s*/, " ").gsub(/\b([a-z]+)_([a-z_]+)\b/) { "#{Regexp.last_match(1)} #{Regexp.last_match(2).tr("_", " ")}" }.strip
      return one if one.empty?

      one = one.sub(/\A./, &:upcase)
      one.match?(/[.!?:]\z/) ? one : "#{one}."
    end

    # A text for a table cell: placeholders in words, no line breaks, and no bar or angle bracket that markdown would read.
    def self.shown(text) = angled(text).gsub(/\s*\n\s*/, " ").strip.gsub("|", "\\\\|").gsub("<", "\\\\<")

    def self.cell(text) = plain(text).gsub("|", "\\\\|")

    # Text as an inline code span, long enough fences for a backtick inside.
    def self.span(text)
      one = text.to_s.gsub(/\s+/, " ").strip
      one.include?("`") ? "`` #{one} ``" : "`#{one}`"
    end

    def self.missing(pages) = pages.flat_map { |page| PageWords.new(page).lines }

    def self.short(klass) = klass.name.split("::").last

    # A workflow by the path that names it under Workflows: Code::Intent::End::Prepare.
    def self.path(klass) = klass.name.delete_prefix("Plastic::Workflows::")

    # The anchor a markdown heading makes from its text.
    def self.anchor(heading) = heading.downcase.gsub(/[^\w\s-]/, "").tr(" ", "-")
  end
end
