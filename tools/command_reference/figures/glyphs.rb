# frozen_string_literal: true

module CommandReference
  module Figures
    # How wide a label is on a drawing, counted letter by letter at the size of the key labels.
    module Glyphs
      SIZE = 11.5
      FALLBACK = 556
      THOUSANDTHS = {
        " " => 278, "," => 278, "." => 278, ":" => 278, "-" => 333,
        "a" => 556, "b" => 556, "c" => 500, "d" => 556, "e" => 556, "f" => 278, "g" => 556, "h" => 556, "i" => 222,
        "j" => 222, "k" => 500, "l" => 222, "m" => 833, "n" => 556, "o" => 556, "p" => 556, "q" => 556, "r" => 333,
        "s" => 500, "t" => 278, "u" => 556, "v" => 500, "w" => 722, "x" => 500, "y" => 500, "z" => 500,
        "A" => 667, "B" => 667, "C" => 722, "D" => 722, "E" => 667, "F" => 611, "G" => 778, "H" => 722, "I" => 278,
        "J" => 500, "K" => 667, "L" => 556, "M" => 833, "N" => 722, "O" => 778, "P" => 667, "Q" => 778, "R" => 722,
        "S" => 667, "T" => 611, "U" => 722, "V" => 667, "W" => 944, "X" => 667, "Y" => 667, "Z" => 611
      }.freeze

      def self.width(text) = text.each_char.sum { |letter| THOUSANDTHS.fetch(letter, FALLBACK) } * SIZE / 1000.0
    end
  end
end
