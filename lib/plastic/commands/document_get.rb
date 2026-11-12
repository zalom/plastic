# frozen_string_literal: true

require_relative "../routine"

module Plastic
  module Commands
    # Fetches one current or immutable document by its qualified reference.
    class DocumentGet < Routine
      argument :reference, label: "REF", text: "plastic://STORE/INTENT/PATH?revision=SHA256"
      option :passage, switch: "--passage N", text: "one-based bounded passage position"
      reads :knowledge

      workflow :code_get_document, next: :noop
    end
  end
end
