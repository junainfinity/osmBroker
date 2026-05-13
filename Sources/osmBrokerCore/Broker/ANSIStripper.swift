import Foundation

/// Strips ANSI escape sequences, terminal control codes, and common spinner
/// artefacts from CLI output so we can stream clean text to API clients.
///
/// PRD §4.4 — "osmBroker strips all ANSI escape codes, terminal formatting,
/// and progress indicators from the CLI's standard output stream."
///
/// Implementation: a single-pass state machine over scalar bytes. Faster and
/// easier to test than a regex (regex on streaming chunks is awkward because
/// an escape can be split across read boundaries). The stateful `Stripper`
/// type tolerates split escapes by retaining the in-progress sequence in its
/// own buffer.
public struct ANSIStripper {

    /// One-shot strip on a complete string. Safe; never throws.
    public static func strip(_ input: String) -> String {
        var stripper = Stripper()
        return stripper.append(input)
    }

    /// Stateful incremental stripper. Use when reading streaming output —
    /// each `append(_:)` returns the stripped text emitted so far for that
    /// chunk; an in-progress escape spanning chunks is held until completed.
    public struct Stripper {
        private enum State {
            case normal
            case esc                 // saw `ESC`
            case csi(buf: String)    // inside `ESC [ ...`
            case osc                 // inside `ESC ] ...` until BEL or ST
            case escIntermediate     // saw `ESC <something>` not [, ]
        }

        private var state: State = .normal

        public init() {}

        /// Append a chunk; return the cleaned characters emitted for it.
        public mutating func append(_ chunk: String) -> String {
            var out = String()
            out.reserveCapacity(chunk.count)

            for ch in chunk {
                switch state {
                case .normal:
                    if ch == "\u{1B}" {                  // ESC
                        state = .esc
                    } else if ch == "\r" {
                        // Treat lone CR (without LF) as a progress redraw and
                        // drop everything since the last LF in `out`. PRD §4.4
                        // — strip progress indicators.
                        if let nlRange = out.range(of: "\n", options: .backwards) {
                            out = String(out[..<nlRange.upperBound])
                        } else {
                            out.removeAll(keepingCapacity: true)
                        }
                    } else if ch == "\u{08}" {           // BS
                        if !out.isEmpty { out.removeLast() }
                    } else if ch == "\u{07}" {           // BEL
                        // drop terminal bell
                    } else {
                        out.append(ch)
                    }

                case .esc:
                    if ch == "[" {
                        state = .csi(buf: "")
                    } else if ch == "]" {
                        state = .osc
                    } else if ch == "(" || ch == ")" || ch == "*" || ch == "+" {
                        // Charset designation — one more byte follows.
                        state = .escIntermediate
                    } else if ch == "\u{1B}" {
                        // ESC ESC — second ESC restarts the sequence.
                        state = .esc
                    } else {
                        // Single-byte escape (e.g. ESC = ESC > ESC c). Drop it.
                        state = .normal
                    }

                case .csi(var buf):
                    // CSI: params/intermediate bytes 0x20..0x3F, terminator 0x40..0x7E.
                    if let scalar = ch.unicodeScalars.first,
                       (0x40...0x7E).contains(scalar.value) {
                        state = .normal                  // sequence complete; drop
                        _ = buf                          // intentionally unused
                    } else {
                        // Cap the buffer to avoid unbounded growth on hostile
                        // input, but stay in `.csi` and keep dropping bytes
                        // until we see a legitimate CSI terminator. Otherwise a
                        // malformed escape would leak its tail as plain text.
                        if buf.count < 128 {
                            buf.append(ch)
                        }
                        state = .csi(buf: buf)
                    }

                case .osc:
                    // OSC ends with BEL (0x07) or ST (ESC \). We don't handle
                    // ST split-across-bytes precisely; ESC inside OSC starts a
                    // potential ST and we accept the following byte as terminator.
                    if ch == "\u{07}" {
                        state = .normal
                    } else if ch == "\u{1B}" {
                        // begin ST — next char terminates regardless
                        state = .escIntermediate
                    }
                    // else: still inside OSC, drop

                case .escIntermediate:
                    // We were inside an ESC X form expecting one more byte;
                    // drop it and return to normal.
                    state = .normal
                }
            }
            return out
        }

        /// Reset to the normal state. Useful between streams.
        public mutating func reset() {
            state = .normal
        }
    }
}
