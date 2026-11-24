# frozen_string_literal: true

module CommandReference
  # Everything one command page says, read from the kernel.
  Page = Data.define(:words, :klass, :kind, :file, :line, :summary, :usage, :arguments, :options, :own_call,
    :entry, :flows, :edges, :endings, :changes, :description) do
    def slug = words.tr(" ", "-")

    def flow(key) = flows.find { |flow| flow.key == key }

    def before(flow) = flows.fetch(flows.index(flow) - 1).key
  end
end
