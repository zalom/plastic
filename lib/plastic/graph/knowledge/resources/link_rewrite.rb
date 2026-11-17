# frozen_string_literal: true

require "pathname"

module Plastic
  module Graph
    module Knowledge
      module Resources
        # Rewrites the relative links of one file after the moves of a sort. A link is kept as it is when it
        # leaves the intent folder, is a web or absolute link, or named no file before the move; the last kind
        # is reported back. `moves` maps old to new paths and `known` lists the files of the folder before the move.
        class LinkRewrite
          Result = Data.define(:text, :unresolved)

          LINK = /(\]\(|(?:href|src)=")([^)"\s]+)/
          EXTERNAL = %r{\A(?:[a-z][a-z0-9+.-]*:|/|#)}i

          def initialize(moves, known)
            @moves = moves
            @known = known.to_set
          end

          def call(path, text)
            unresolved = []
            rewritten = text.gsub(LINK) { "#{Regexp.last_match(1)}#{target(Regexp.last_match(2), path, unresolved)}" }
            Result.new(rewritten, unresolved)
          end

          private

          def target(link, path, unresolved)
            return link if EXTERNAL.match?(link)

            name, tail = link.split(/(?=[#?])/, 2)
            found = Pathname.new(File.join(File.dirname(path), name)).cleanpath.to_s
            return unresolved.push(link) && link unless @known.include?(found)

            moved?(found, path) ? "#{relative(found, path)}#{tail}" : link
          end

          def moved?(*paths) = paths.any? { |path| @moves.key?(path) }

          def relative(found, path)
            Pathname.new(@moves.fetch(found, found)).relative_path_from(Pathname.new(File.dirname(@moves.fetch(path, path)))).to_s
          end
        end
      end
    end
  end
end
