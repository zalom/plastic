# encoding: UTF-8

module SessionStartHook
  # One `## Active` / `## Future` section parse, shared by the global
  # INDEX.md and a project's own INDEX.md.
  module IndexFile
    HEADER_SECTIONS = { "## Active" => :active, "## Future" => :future }.freeze

    def self.parse(path)
      sections = { active: [], future: [] }
      scan(path, sections)
      [sections[:active], sections[:future]]
    end

    def self.scan(path, sections)
      cursor = Cursor.new(nil)
      File.readlines(path).each do |line|
        cursor.advance(line)
        accumulate(sections, cursor.section, line)
      end
    end

    def self.accumulate(sections, section, line)
      return unless section.is_a?(Symbol)

      stripped = line.strip
      return unless stripped.start_with?("- [")

      sections[section] << stripped if sections.key?(section)
    end

    def self.section_for(line)
      HEADER_SECTIONS.find { |prefix, _| line.start_with?(prefix) }&.last
    end

    # Tracks which `##` section a line stream is currently inside, so the
    # same running state never needs to come back as a parameter the next
    # line's classification branches on.
    class Cursor
      attr_reader :section

      def initialize(section)
        @section = section
      end

      def advance(line)
        return unless line.start_with?("## ")

        @section = IndexFile.section_for(line)
      end
    end
  end
end
