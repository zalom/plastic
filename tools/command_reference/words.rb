# frozen_string_literal: true

module CommandReference
  # Words cut into lines of a given width, and short names.
  module Words
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

    def self.cell(text) = plain(text).gsub("|", "\\\\|")

    # Text as an inline code span, long enough fences for a backtick inside.
    def self.span(text)
      one = text.to_s.gsub(/\s+/, " ").strip
      one.include?("`") ? "`` #{one} ``" : "`#{one}`"
    end

    def self.short(klass) = klass.name.split("::").last

    # A workflow by the path that names it under Workflows: Code::Intent::End::Prepare.
    def self.path(klass) = klass.name.delete_prefix("Plastic::Workflows::")

    # The anchor a markdown heading makes from its text.
    def self.anchor(heading) = heading.downcase.gsub(/[^\w\s-]/, "").tr(" ", "-")
  end
end
