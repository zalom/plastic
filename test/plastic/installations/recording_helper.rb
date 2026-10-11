# frozen_string_literal: true

require "stringio"
require_relative "../commands/installer_helper"
require_relative "../../../scripts/lib/plastic/workflows/installation"
require_relative "../../../scripts/lib/plastic/installations"

# An install into a throwaway home and the record it makes for one harness.
module RecordingHelper
  include InstallerHelper

  def installation = Plastic::Workflows::Installation.of(call_context(harness: scoped_harness))

  def installed_into(key, argv: [])
    Plastic::Workflows::Installation.capture { installation.run(selected: [key], argv:, input: StringIO.new) }
  end

  def recorded(name) = Plastic::Installations::Recording.new(installation, Plastic::Harnesses.fetch(name)).call
end
