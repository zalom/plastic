# frozen_string_literal: true

require_relative "installer_status"

module Plastic
  module Commands
    class Rollback < InstallerStatus
      option :dry_run, switch: "--dry-run", default: false, text: "print the verified release plan without writing files"
    end
  end
end
