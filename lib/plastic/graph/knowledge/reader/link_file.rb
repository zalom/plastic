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
            Link.from_entry(entry, now) || raise(Invalid, "#{StoreFolder::INDEX} lists a link that needs a from_ref, a to_ref and a kind of #{Link::KINDS.join(", ")}: #{entry.inspect}")
          end
        end
      end
    end
  end
end
