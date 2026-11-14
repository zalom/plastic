# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"

# Writes the three files of one release into a folder of the test's home. The
# archive holds plain bytes: the kernel only checks its checksum.
module ReleaseFixture
  def release_files(version: "2.0.3", name: "release")
    directory = FileUtils.mkdir_p(File.join(@home, name)).first
    archive = File.join(directory, "plastic.tgz")
    File.binwrite(archive, "archive of #{version}")
    File.write(File.join(directory, "plastic.tgz.sha256"), "#{Digest::SHA256.file(archive).hexdigest}  plastic.tgz\n")
    File.write(File.join(directory, "plastic.manifest.json"), JSON.generate("release" => { "version" => version }))
    directory
  end
end
