# frozen_string_literal: true

module Plastic
  module Graph
    module Knowledge
      class Roadmap
        module Parse
          # One roadmap item read from its joined lines, or the reason it cannot be read.
          class ItemLine
            LEAD = /\A-\s*\[([ xX])\]\s+(\S+)\s+(.*)\z/
            STATUS = /[—-]\s*(queued|delivering|delivered|abandoned|blocked)\b/

            def initialize(joined, batch)
              @joined = joined
              @batch = batch
              @lead = joined.match(LEAD)
              @status = @lead && @lead[3].match(STATUS)
            end

            def problem = lead_problem || status_problem || id_problem

            def item = Item.new(item: id, batch: @batch, title: @status.pre_match.strip, status: @status[1])

            private

            def id = @lead[2]

            def lead_problem = ("cannot read roadmap item #{@joined.inspect}" unless @lead)

            def status_problem = ("no status on roadmap item #{@joined.inspect}" unless @status)

            def id_problem = ("not a plain id: #{id.inspect}" unless TOKEN.match?(id))
          end
        end
      end
    end
  end
end
