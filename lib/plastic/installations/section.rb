# frozen_string_literal: true

require_relative "rewrite"

module Plastic
  module Installations
    # A marked section an install wrote into an instruction file, found by
    # its begin and end markers.
    Section = Data.define(:file, :opening, :closing) do
      def self.from_h(hash) = new(file: hash["file"], opening: hash["begin"], closing: hash["end"])

      def strip
        return unless File.file?(file)

        text = File.read(file)
        stripped = text.sub(pattern, "")
        Rewrite.text(file, stripped) unless stripped == text
      end

      private

      def pattern = /\n?^#{Regexp.escape(opening)}.*?-->\n.*?^#{Regexp.escape(closing)}\n?/m
    end
  end
end
