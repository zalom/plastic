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

          # One link the rewrite changed: the link as it was and the link it is now.
          Change = Data.define(:was, :now) do
            def to_s = "#{was} -> #{now}"
          end

          LINK = /(\]\(|(?:href|src)=")([^)"\s]+)/
          EXTERNAL = %r{\A(?:[a-z][a-z0-9+.-]*:|/|#|\?)}i

          # The store paths that the relative links of `text`, the file at the store path `path`, name.
          def self.targets(path, text) = text.scan(LINK).map(&:last).reject { |link| EXTERNAL.match?(link) }.map { |link| resolved(link, path) }

          def self.resolved(link, path) = Pathname.new(File.join(File.dirname(path), link.split(/(?=[#?])/, 2).first)).cleanpath.to_s

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
            changed << Change.new(link, now) unless now == link
            "#{prefix}#{now}"
          end

          def target(link, path, unresolved)
            return link if EXTERNAL.match?(link)

            tail = link.split(/(?=[#?])/, 2)[1]
            found = LinkRewrite.resolved(link, path)
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
