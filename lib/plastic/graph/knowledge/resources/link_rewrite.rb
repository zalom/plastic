# frozen_string_literal: true

require "pathname"

module Plastic
  module Graph
    module Knowledge
      module Resources
        # Rewrites the relative links of one file after the moves of a sort. A link is kept as it is when it is a web or
        # absolute link, or named no file in the store folder before the move; the last kind is reported back. Every path
        # is relative to the store folder; `moves` maps old to new paths and `known` holds the files before the move.
        class LinkRewrite
          Result = Data.define(:text, :unresolved, :changed)

          LINK = /(\]\(|(?:href|src)=")([^)"\s]+)/
          EXTERNAL = %r{\A(?:[a-z][a-z0-9+.-]*:|/|#|\?)}i

          def initialize(moves, known)
            @moves = moves
            @known = known
          end

          def call(path, text)
            unresolved = []
            changed = []
            rewritten = text.gsub(LINK) { relinked(Regexp.last_match(1), Regexp.last_match(2), path, unresolved, changed) }
            Result.new(rewritten, unresolved, changed)
          end

          private

          def relinked(prefix, link, path, unresolved, changed)
            now = target(link, path, unresolved)
            changed << "#{link} -> #{now}" unless now == link
            "#{prefix}#{now}"
          end

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
