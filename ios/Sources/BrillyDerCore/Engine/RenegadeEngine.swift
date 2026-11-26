import Foundation
import CRenegadeEngine

/// MIT-licensed Renegade v1.3.1 C++20 ARM64 NEON NNUE engine (~3300–3450+ CCRL Elo offline).
/// Pure self-play NNUE weights (`renegade-net-36.bin`) are memory-mapped read-only (`mmap`)
/// for near-zero dirty RAM usage on iOS. Gracefully falls back to `BrillyNativeEngine` if unavailable.
public actor RenegadeEngine: ChessEngine {
    public nonisolated let engineName = "BrillyChess NNUE (Renegade MIT)"
    public nonisolated let engineLicense = "MIT License (Copyright © 2022–2026 Krisztián Peőcz)"

    private final class SearchRequestTracker: @unchecked Sendable {
        private let lock = NSLock()
        private var nextId: UInt64 = 1
        private var activeId: UInt64 = 0
        private var cancelledIds: Set<UInt64> = []

        func allocate() -> UInt64 {
            lock.lock()
            defer { lock.unlock() }
            let id = nextId
            nextId &+= 1
            return id
        }

        /// Returns false if this request was already cancelled before entering C++ search.
        func begin(_ id: UInt64) -> Bool {
            lock.lock()
            defer { lock.unlock() }
            if cancelledIds.remove(id) != nil {
                return false
            }
            activeId = id
            return true
        }

        func end(_ id: UInt64) {
            lock.lock()
            defer { lock.unlock() }
            if activeId == id {
                activeId = 0
            }
            cancelledIds.remove(id)
        }

        /// Returns true iff `id` is the currently executing C++ search and should be aborted.
        func cancel(_ id: UInt64) -> Bool {
            lock.lock()
            defer { lock.unlock() }
            if activeId == id {
                return true
            }
            cancelledIds.insert(id)
            return false
        }
    }

    private static let searchQueue = DispatchQueue(
        label: "com.brillyder.renegade.engine",
        qos: .userInitiated
    )
    private static let requestTracker = SearchRequestTracker()

    private let fallback = BrillyNativeEngine()
    private var isReady: Bool = false
    private var initAttempted: Bool = false

    public init() {}

    /// Returns true if the bundled Renegade NNUE weights (`renegade-net-36.bin`)
    /// are memory-mapped and ready for native C++20 NEON search.
    public func isNativeNNUEReady() -> Bool {
        ensureInitialized()
    }

    private func ensureInitialized() -> Bool {
        if initAttempted { return isReady }
        initAttempted = true
        guard let url = Bundle.module.url(forResource: "renegade-net-36", withExtension: "bin") else {
            isReady = false
            return false
        }
        isReady = url.path.withCString { cPath in
            renegade_init(cPath, 16)
        }
        return isReady
    }

    public func clearHash() async {
        guard isReady else { return }
        await withCheckedContinuation { continuation in
            Self.searchQueue.async {
                renegade_clear_hash()
                continuation.resume()
            }
        }
    }

    public func analyze(
        fen: String,
        depth: Int = 14,
        multiPV: Int = 2,
        maxTimeMs: Int? = 250
    ) async throws -> EngineEval {
        try Task.checkCancellation()
        guard ensureInitialized() else {
            return try await fallback.analyze(fen: fen, depth: depth, multiPV: multiPV, maxTimeMs: maxTimeMs)
        }

        // Validate & normalize FEN via ChessBoard first so 4/5-field FENs and impossible castling rights are sanitized
        let board = try ChessBoard(fen: fen)
        let normalizedFen = board.fen
        let timeMs = Int32(max(20, maxTimeMs ?? 250))
        let maxD = Int32(max(1, min(30, depth)))
        let pvCount = Int32(max(1, min(3, multiPV)))
        let requestId = Self.requestTracker.allocate()

        let raw: (ok: Bool, result: RenegadeAnalysisResult) = await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                Self.searchQueue.async {
                    guard Self.requestTracker.begin(requestId) else {
                        continuation.resume(returning: (false, RenegadeAnalysisResult()))
                        return
                    }
                    defer { Self.requestTracker.end(requestId) }
                    var out = RenegadeAnalysisResult()
                    let ok = normalizedFen.withCString { cFen in
                        renegade_analyze(cFen, maxD, pvCount, timeMs, &out)
                    }
                    continuation.resume(returning: (ok, out))
                }
            }
        } onCancel: {
            if Self.requestTracker.cancel(requestId) {
                renegade_abort()
            }
        }

        try Task.checkCancellation()
        guard raw.ok else {
            return try await fallback.analyze(fen: fen, depth: depth, multiPV: multiPV, maxTimeMs: maxTimeMs)
        }

        let res = raw.result
        if res.is_terminal {
            let score: EngineScore
            if res.is_checkmate {
                score = ChessMath.buildEngineScore(
                    cpWhite: board.turn == .white ? -10000 : 10000,
                    mateWhite: 0,
                    isCheckmate: true,
                    winnerColor: board.turn.opposite
                )
            } else {
                score = ChessMath.buildEngineScore(cpWhite: 0)
            }
            return EngineEval(fen: fen, depth: 0, bestMoveUci: "", pv: [], score: score, lines: [])
        }

        let isWhiteTurn = res.turn_is_white
        let count = Int(min(3, max(0, res.line_count)))
        let tupleLines = [res.lines.0, res.lines.1, res.lines.2]

        var builtLines: [MultiPvLine] = []
        builtLines.reserveCapacity(count)

        for i in 0..<count {
            let line = tupleLines[i]
            let bm = Self.cString(from: line.best_move_uci)
            let pvStr = Self.cString(from: line.pv_uci)
            let pvMoves = pvStr.split(separator: " ").map(String.init)

            let cpWhite = isWhiteTurn ? Int(line.score_cp_side) : -Int(line.score_cp_side)
            let mateWhite: Int? = line.mate_side == 0
                ? nil
                : (isWhiteTurn ? Int(line.mate_side) : -Int(line.mate_side))
            let score = ChessMath.buildEngineScore(cpWhite: cpWhite, mateWhite: mateWhite)

            builtLines.append(MultiPvLine(
                multipv: i + 1,
                bestMoveUci: bm,
                pv: pvMoves.isEmpty ? (bm.isEmpty ? [] : [bm]) : pvMoves,
                score: score
            ))
        }

        guard let top = builtLines.first else {
            return try await fallback.analyze(fen: fen, depth: depth, multiPV: multiPV, maxTimeMs: maxTimeMs)
        }

        return EngineEval(
            fen: fen,
            depth: max(1, Int(res.depth)),
            bestMoveUci: top.bestMoveUci,
            pv: top.pv,
            score: top.score,
            lines: builtLines
        )
    }

    private static func cString<T>(from tuple: T) -> String {
        withUnsafeBytes(of: tuple) { raw in
            let ptr = raw.bindMemory(to: CChar.self)
            guard let base = ptr.baseAddress else { return "" }
            return String(cString: base)
        }
    }
}
