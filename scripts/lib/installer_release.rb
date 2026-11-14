# frozen_string_literal: true

require_relative "../../lib/plastic/installations/launcher_link"
require_relative "../../lib/plastic/installations/release_files"

module InstallerRelease
  LauncherLink = Plastic::Installations::LauncherLink
  ReleaseFiles = Plastic::Installations::ReleaseFiles
  VerificationError = Plastic::Installations::VerificationError
end

require_relative "installer_release/manifest"
require_relative "installer_release/archive"
require_relative "installer_release/staging"
require_relative "installer_release/activation"
require_relative "installer_release/home_sync"
require_relative "installer_release/release_install"
