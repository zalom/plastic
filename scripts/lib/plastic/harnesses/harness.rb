# frozen_string_literal: true

module Plastic
  module Harnesses
    # What Plastic knows about one harness: the variables its tool shells
    # carry, the folder its transcripts live in, its process name, an event
    # field only it writes, the hook command of each event, its settings file
    # under the home, and the doctor that checks it.
    Harness = Data.define(:name, :session_variables, :transcript, :process, :event_field, :events, :settings, :doctor)
  end
end
