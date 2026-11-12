# frozen_string_literal: true

module Plastic
  class CLI
    class Command
      # One word a command takes. A rest argument takes every word left; an
      # optional one may be missing.
      Argument = Data.define(:name, :label, :text, :rest, :optional) do
        def usage
          value = rest ? "#{label}..." : label
          optional ? "[#{value}]" : value
        end

        # This argument's value in `words`, the words left after the
        # switches. A blank value counts as missing: nil when optional, a
        # Usage error when not.
        def read(words, index)
          value = rest ? words.drop(index).join(" ") : words[index].to_s
          return value unless value.strip.empty?
          raise Usage, "missing #{label}" unless optional
        end
      end
    end
  end
end
