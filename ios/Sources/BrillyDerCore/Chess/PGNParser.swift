import Foundation

public struct ParsedPGNMove: Hashable, Sendable {
    public let applied: AppliedMove
    public let comment: String?
    public let clockText: String?
    public let clockSeconds: Double?
}

public struct ParsedPGNGame: Sendable {
    public let headers: [String: String]
    public let startFen: String
    public let moves: [ParsedPGNMove]
    public let finalBoard: ChessBoard
    public let result: String
}

public enum PGNParser {
    public static func parse(_ pgn: String) throws -> ParsedPGNGame {
        let normalized = pgn.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        var headers: [String: String] = [:]
        var bodyLines: [String] = []

        for line in normalized.split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("[") && trimmed.hasSuffix("]"), let (key, val) = parseHeaderLine(trimmed) {
                headers[key] = val
            } else {
                bodyLines.append(String(line))
            }
        }

        let startFen = headers["FEN"] ?? ChessBoard.initialFEN
        var board = try ChessBoard(fen: startFen)
        let movetext = bodyLines.joined(separator: "\n")
        let tokens = tokenizeMovetext(movetext)

        var parsedMoves: [ParsedPGNMove] = []
        var parsedResult = headers["Result"] ?? "*"

        for token in tokens {
            switch token {
            case .result(let res):
                parsedResult = res
            case .comment(let text):
                if !parsedMoves.isEmpty {
                    let prev = parsedMoves.removeLast()
                    let mergedComment = [prev.comment, text].compactMap { $0 }.joined(separator: " ")
                    let clkText = extractClockText(from: mergedComment) ?? prev.clockText
                    let clkSec = clkText.flatMap(parseClockSeconds) ?? prev.clockSeconds
                    parsedMoves.append(ParsedPGNMove(
                        applied: prev.applied,
                        comment: mergedComment,
                        clockText: clkText,
                        clockSeconds: clkSec
                    ))
                }
            case .san(let rawSan):
                let applied = try board.apply(san: rawSan)
                parsedMoves.append(ParsedPGNMove(
                    applied: applied,
                    comment: nil,
                    clockText: nil,
                    clockSeconds: nil
                ))
            }
        }

        return ParsedPGNGame(
            headers: headers,
            startFen: startFen,
            moves: parsedMoves,
            finalBoard: board,
            result: parsedResult
        )
    }

    public static func extractClockText(from comment: String) -> String? {
        guard let range = comment.range(of: #"\[%clk\s+([0-9:.]+)\]"#, options: .regularExpression) else {
            return nil
        }
        let match = String(comment[range])
        return match
            .replacingOccurrences(of: "[%clk", with: "")
            .replacingOccurrences(of: "]", with: "")
            .trimmingCharacters(in: .whitespaces)
    }

    public static func parseClockSeconds(_ clockText: String) -> Double? {
        let parts = clockText.split(separator: ":").compactMap { Double($0) }
        switch parts.count {
        case 3: return parts[0] * 3600 + parts[1] * 60 + parts[2]
        case 2: return parts[0] * 60 + parts[1]
        case 1: return parts[0]
        default: return nil
        }
    }

    public static func parseTimeControl(_ raw: String?) -> (initialSeconds: Double, incrementSeconds: Double)? {
        guard let raw else { return nil }
        let parts = raw.split(separator: "+")
        guard let initial = parts.first.flatMap({ Double($0) }) else { return nil }
        let inc = parts.count > 1 ? (Double(parts[1]) ?? 0) : 0
        return (initial, inc)
    }

    // MARK: - Private Tokenizer

    private enum Token {
        case san(String)
        case comment(String)
        case result(String)
    }

    private static func parseHeaderLine(_ line: String) -> (String, String)? {
        guard let firstQuote = line.firstIndex(of: "\""),
              let lastQuote = line.lastIndex(of: "\""),
              firstQuote < lastQuote else { return nil }
        let keyPart = line[line.index(after: line.startIndex)..<firstQuote]
            .trimmingCharacters(in: .whitespaces)
        guard !keyPart.isEmpty else { return nil }
        let value = String(line[line.index(after: firstQuote)..<lastQuote])
            .replacingOccurrences(of: "\\\"", with: "\"")
            .replacingOccurrences(of: "\\\\", with: "\\")
        return (keyPart, value)
    }

    private static func tokenizeMovetext(_ text: String) -> [Token] {
        var tokens: [Token] = []
        let chars = Array(text)
        var i = 0
        var variationDepth = 0

        while i < chars.count {
            let ch = chars[i]

            if ch == ";" {
                while i < chars.count && chars[i] != "\n" { i += 1 }
                continue
            }
            if ch == "(" {
                variationDepth += 1
                i += 1
                continue
            }
            if ch == ")" {
                variationDepth = max(0, variationDepth - 1)
                i += 1
                continue
            }
            if ch == "{" {
                i += 1
                let start = i
                while i < chars.count && chars[i] != "}" { i += 1 }
                if variationDepth == 0 {
                    let comment = String(chars[start..<i]).trimmingCharacters(in: .whitespacesAndNewlines)
                    if !comment.isEmpty { tokens.append(.comment(comment)) }
                }
                if i < chars.count { i += 1 }
                continue
            }
            if variationDepth > 0 || ch.isWhitespace {
                i += 1
                continue
            }

            let start = i
            while i < chars.count && !chars[i].isWhitespace &&
                  chars[i] != "{" && chars[i] != "(" && chars[i] != ")" && chars[i] != ";" {
                i += 1
            }
            let raw = String(chars[start..<i])
            if raw.isEmpty || raw.hasPrefix("$") { continue }
            if raw == "1-0" || raw == "0-1" || raw == "1/2-1/2" || raw == "*" {
                tokens.append(.result(raw))
                continue
            }
            // Strip leading move numbers like "1." or "12..." or "1.e4"
            var candidate = raw
            if let dotIdx = candidate.lastIndex(of: ".") {
                let prefix = candidate[..<dotIdx]
                if prefix.allSatisfy({ $0.isNumber || $0 == "." }) {
                    candidate = String(candidate[candidate.index(after: dotIdx)...])
                }
            }
            if candidate.isEmpty || candidate == "e.p." || candidate.allSatisfy({ $0.isNumber || $0 == "." }) {
                continue
            }
            tokens.append(.san(candidate))
        }
        return tokens
    }
}
