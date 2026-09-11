# encoding: UTF-8
# frozen_string_literal: true

require "json"
require "digest"

# CoreIntegrity (intent 340, G7, n1): re-hashes the files an installed
# ~/.plastic/manifest.json lists, so the runner's own "am I running trusted
# code" check has one implementation. scripts/doctor.rb's
# Doctor#check_install_integrity does this same arithmetic inline today,
# per-agent (Codex/Hermes/Claude), against each agent's own manifest; this
# module is not a refactor of that (out of scope for this node), it exists
# so the runner - and a later node that points doctor at it - never have to
# reimplement the same hashing loop a third time.
#
# Pure and side-effect-free: `check` takes plastic_home: and never raises
# across its boundary. A missing, unreadable, or non-JSON manifest.json is a
# named refusal (`reason:`), never an exception. A manifest-listed file that
# no longer exists is reported under `missing`, distinct from `drifted` (a
# file that exists but no longer hashes to the manifest's recorded value).
module CoreIntegrity
  module_function

  def check(plastic_home:)
    manifest_path = File.join(plastic_home.to_s, "manifest.json")
    return refusal("manifest.json not found at #{manifest_path}") unless File.exist?(manifest_path)

    raw = begin
      File.read(manifest_path)
    rescue StandardError => e
      return refusal("manifest.json is unreadable: #{e.message}")
    end

    data = begin
      JSON.parse(raw)
    rescue JSON::ParserError => e
      return refusal("manifest.json is not valid JSON: #{e.message}")
    end

    files = data.is_a?(Hash) ? data["files"] : nil
    return refusal("manifest.json's files: is not a mapping") unless files.is_a?(Hash)

    drifted = []
    missing = []
    files.each do |path, expected_hash|
      unless File.exist?(path)
        missing << path
        next
      end

      # v1 minor 6/row 11.16: a tracked file that exists but cannot be read
      # (permissions changed under this process) must never raise out of a
      # module whose whole contract is "never raises across its boundary" -
      # unreadable is reported the same way a hash mismatch is: this
      # process cannot confirm the file matches what the manifest expects,
      # which is exactly what `drifted` already means.
      actual_hash = begin
        Digest::SHA256.file(path).hexdigest
      rescue SystemCallError
        nil
      end
      drifted << path if actual_hash.nil? || actual_hash != expected_hash
    end

    { ok: drifted.empty? && missing.empty?, drifted: drifted, missing: missing, reason: nil }
  end

  def refusal(reason)
    { ok: false, drifted: [], missing: [], reason: reason }
  end
end
