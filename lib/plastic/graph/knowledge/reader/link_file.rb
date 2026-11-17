# frozen_string_literal: true

require_relative "index_file"
require_relative "../link"

module Plastic
  module Graph
    module Knowledge
      class Reader
        # The links of store/index.json as a file of their own. A link is kept as written, whatever its ends name.
        # With a printed row for the part, the links this home holds are replaced by the ones the file lists; with
        # none, the links of the file are added and no link is removed. The links of another origin stay.
        class LinkFile < IndexFile
          def initialize(text, origin_id, replace)
            super(text, origin_id)
            @replace = replace
          end

          def apply(batch, now)
            batch.remove(:links) if @replace
            batch.put_all(:links, links(now))
          end

          private

          def links(now) = listed("links").map { |entry| link(entry, now) }

          def link(entry, now)
            from_ref, to_ref, kind = entry.values_at("from_ref", "to_ref", "kind")
            return { from_ref:, to_ref:, kind:, at: entry["at"] || now } if refs?(from_ref, to_ref) && Link::KINDS.include?(kind)

            raise Invalid, "#{StoreFolder::INDEX} lists a link that needs a from_ref, a to_ref and a kind of #{Link::KINDS.join(", ")}: #{entry.inspect}"
          end

          def refs?(*refs) = refs.all? { |ref| ref.is_a?(String) && !ref.empty? }
        end
      end
    end
  end
end
