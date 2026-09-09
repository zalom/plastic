# encoding: UTF-8
# frozen_string_literal: true

require "digest"

# PacketWrapper (intent 338, G5, n1): the trust boundary a node packet is
# built over. A data block carries text other agents and the owner wrote,
# and is opened by `<<<PLASTIC-DATA:<token> label="..." source="...">>>` and
# closed by `<<<END-PLASTIC-DATA:<token>>>`. The token is content-derived
# (spec D4), so the same payloads always produce the same token and the
# packet stays deterministic; the escaping rule (spec D5) runs on every
# payload independently of the token, so a payload carrying this packet's
# own closing marker still cannot close its block. Attribute values
# (`label`, `source`) are sanitized separately, by a whitelist (spec D5a),
# because they are not payload text and the payload escaping rule does not
# cover them.
#
# Pure and side-effect-free: no I/O, no clock, nothing raised across the
# boundary. `estimate_tokens` is the one arithmetic every budget in this
# delivery is spent in (spec D6): bytes over four, rounded.
module PacketWrapper
  module_function

  MARKER_OPEN = "<<<PLASTIC-DATA:"
  MARKER_CLOSE = "<<<END-PLASTIC-DATA:"
  ATTR_MAX = 200

  # The attribute whitelist (spec D5a): anything outside this class becomes
  # `_`. A quote, an angle bracket, a backslash, a newline and a carriage
  # return are therefore all impossible in a marker line.
  ATTR_SAFE_CHARS_RE = %r{[^A-Za-z0-9 _.,:#/@+=-]}.freeze

  OPEN_LINE_RE = /\A#{Regexp.escape(MARKER_OPEN)}([0-9a-f]+) label="([^"]*)" source="([^"]*)">>>\z/.freeze
  CLOSE_LINE_RE = /\A#{Regexp.escape(MARKER_CLOSE)}([0-9a-f]+)>>>\z/.freeze

  # The first twelve hex characters of the SHA-256 over the payloads joined
  # by a newline (spec D4): fixed per packet, unguessable from any single
  # record file, deterministic across two builds of the same payloads.
  def boundary_token(payloads)
    Digest::SHA256.hexdigest(Array(payloads).map(&:to_s).join("\n"))[0, 12]
  end

  # One-way marker escaping (spec D5), plus a UTF-8 scrub (matrix 1.10) so
  # one invalid byte anywhere in a record never raises the whole packet
  # build. Runs regardless of what token trails the marker text, because a
  # payload copied from an earlier packet may carry ANY token, not only this
  # one (matrix 1.2's concern applied to escaping rather than to the token
  # itself).
  def escape(payload)
    text = payload.to_s.scrub
    text = text.gsub(MARKER_OPEN) { "<<<\\PLASTIC-DATA:" }
    text.gsub(MARKER_CLOSE) { "<<<\\END-PLASTIC-DATA:" }
  end

  # Whitelist-sanitize and truncate a marker attribute value (spec D5a).
  # Every character outside the whitelist becomes `_`; the result is
  # truncated to ATTR_MAX characters, so neither a hostile value nor a
  # multi-kilobyte one can escape or bloat a marker line.
  def attr_safe(value)
    value.to_s.scrub.gsub(ATTR_SAFE_CHARS_RE, "_")[0, ATTR_MAX]
  end

  # One complete, closed data block ending in a newline. The payload is
  # escaped and scrubbed first; both markers sit alone on their own line
  # (matrix 1.4), even when the payload is empty (matrix 1.9).
  def wrap(payload, label:, source:, token:)
    body = escape(payload)
    body += "\n" unless body.empty? || body.end_with?("\n")
    open_line = "#{MARKER_OPEN}#{token} label=\"#{attr_safe(label)}\" source=\"#{attr_safe(source)}\">>>\n"
    close_line = "#{MARKER_CLOSE}#{token}>>>\n"
    "#{open_line}#{body}#{close_line}"
  end

  # [{label:, source:, payload:}], in order. Matches markers case-sensitively
  # (matrix 1.16: no `/i`, ever) and closes a block only on a close marker
  # whose token matches the block's own opening token, so a stray marker for
  # a different token found mid-payload (which the escaping rule already
  # makes unreachable from real payload text) is never mistaken for this
  # block's close.
  def unwrap(text)
    lines = text.to_s.each_line.to_a
    blocks = []
    i = 0
    while i < lines.length
      m = lines[i].chomp("\n").match(OPEN_LINE_RE)
      unless m
        i += 1
        next
      end

      token, label, source = m[1], m[2], m[3]
      payload_lines = []
      i += 1
      while i < lines.length
        cm = lines[i].chomp("\n").match(CLOSE_LINE_RE)
        break if cm && cm[1] == token

        payload_lines << lines[i]
        i += 1
      end
      blocks << { label: label, source: source, payload: payload_lines.join }
      i += 1
    end
    blocks
  end

  # (bytes / 4.0).round (spec D6): the estimate G10 measures against. Taken
  # over bytesize, never characters, so multi-byte text is never
  # under-counted.
  def estimate_tokens(text)
    (text.to_s.bytesize / 4.0).round
  end
end
