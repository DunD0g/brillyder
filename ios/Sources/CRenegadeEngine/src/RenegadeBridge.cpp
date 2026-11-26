#include "RenegadeBridge.h"
#include "Magics.h"
#include "Neural.h"
#include "Position.h"
#include "Search.h"
#include "Settings.h"

#include <algorithm>
#include <atomic>
#include <cstring>
#include <memory>
#include <mutex>
#include <string>
#include <vector>

namespace {
std::mutex gEngineMutex;
Search* gSearch = nullptr;
std::atomic<Search*> gSearchAtomic{nullptr};
std::atomic<uint64_t> gActiveRequestId{0};
std::atomic<uint64_t> gMaxAbortedRequestId{0};
bool gInitialized = false;

bool isRequestAborted(uint64_t requestId) {
    return requestId != 0 && gMaxAbortedRequestId.load(std::memory_order_acquire) >= requestId;
}
}

bool renegade_init(const char* network_path, int32_t hash_mb) {
    std::lock_guard<std::mutex> lock(gEngineMutex);
    if (gInitialized) return true;

    GenerateMagicTables();
    if (!LoadNetworkFromPath(network_path)) {
        return false;
    }

    Settings::UseUCI = true;
    Settings::Threads = 1;
    Settings::Hash = std::clamp<int>(hash_mb, 4, 64);

    // Intentionally immortal singleton so GCD searchQueue never hits static-teardown UAF at app exit
    Search* s = new Search();
    if (!s->TranspositionTable.SetSize(Settings::Hash, 1)) {
        delete s;
        return false;
    }
    s->ResetState(false);
    gSearch = s;
    gSearchAtomic.store(s, std::memory_order_release);
    gInitialized = true;
    return true;
}

void renegade_clear_hash(void) {
    std::lock_guard<std::mutex> lock(gEngineMutex);
    if (gSearch) {
        gSearch->ResetState(true);
    }
}

void renegade_abort_request(uint64_t request_id) {
    if (request_id == 0) return;
    uint64_t prev = gMaxAbortedRequestId.load(std::memory_order_relaxed);
    while (prev < request_id && !gMaxAbortedRequestId.compare_exchange_weak(prev, request_id, std::memory_order_release, std::memory_order_relaxed)) {}

    Search* s = gSearchAtomic.load(std::memory_order_acquire);
    if (s && gActiveRequestId.load(std::memory_order_acquire) == request_id) {
        s->Aborting.store(true, std::memory_order_relaxed);
    }
}

bool renegade_analyze(
    const char* fen,
    int32_t max_depth,
    int32_t multi_pv,
    int32_t max_time_ms,
    uint64_t request_id,
    RenegadeAnalysisResult* out_result
) {
    if (!fen || !out_result) return false;
    std::memset(out_result, 0, sizeof(RenegadeAnalysisResult));
    if (isRequestAborted(request_id)) return false;

    std::lock_guard<std::mutex> lock(gEngineMutex);
    if (!gInitialized || !gSearch) return false;
    if (isRequestAborted(request_id)) return false;

    Position pos((std::string(fen)));
    // Renegade's NNUE output buckets are trained for standard <=32-piece chess positions;
    // reject abnormal >32-piece custom editor positions so caller falls back cleanly.
    if (Popcount(pos.GetOccupancy()) > 32) {
        return false;
    }
    out_result->turn_is_white = (pos.Turn() == Side::White);

    MoveList legalMoves{};
    pos.GenerateAllLegalMoves(legalMoves);
    if (legalMoves.size() == 0) {
        out_result->is_terminal = true;
        out_result->is_checkmate = pos.IsInCheck();
        out_result->line_count = 0;
        out_result->depth = 0;
        return true;
    }

    const int clampedPV = std::clamp<int>(multi_pv, 1, std::min<int>(3, static_cast<int>(legalMoves.size())));
    const int clampedDepth = std::clamp<int>(max_depth, 1, 30);

    // Split time budget smoothly across MultiPV lines (62% for PV1, remaining split across PV2..3)
    auto budgetForLine = [&](int pvIdx) -> int {
        if (max_time_ms <= 0) return 0;
        if (clampedPV == 1) return max_time_ms;
        if (pvIdx == 0) return std::max(15, (max_time_ms * 62) / 100);
        const int rest = std::max(15, max_time_ms - (max_time_ms * 62) / 100);
        return std::max(12, rest / (clampedPV - 1));
    };

    gSearch->RootExcludedMoves.clear();
    gActiveRequestId.store(request_id, std::memory_order_release);

    struct ActiveRequestGuard {
        ~ActiveRequestGuard() {
            gActiveRequestId.store(0, std::memory_order_release);
            if (gSearch) gSearch->RootExcludedMoves.clear();
        }
    } activeGuard;

    struct RawLine {
        int rawScore;
        int cpSide;
        int mateSide;
        int depth;
        Move bestMove;
        std::vector<Move> pv;
    };
    std::vector<RawLine> foundLines;
    foundLines.reserve(clampedPV);

    for (int i = 0; i < clampedPV; ++i) {
        if (isRequestAborted(request_id)) {
            return false;
        }

        SearchParams params{};
        params.depth = clampedDepth;
        params.movetime = budgetForLine(i);

        Results res = gSearch->SearchSinglethreaded(pos, params);
        if (isRequestAborted(request_id)) {
            return false;
        }

        Move bm = res.BestMove();
        if (bm.IsNull()) {
            // Do not fabricate a bogus 0cp move if search produced no move
            break;
        }

        RawLine line{};
        line.rawScore = res.score;
        line.depth = std::max(1, res.depth);
        line.bestMove = bm;
        line.pv = res.pv.empty() ? std::vector<Move>{bm} : res.pv;
        if (IsMateScore(res.score)) {
            const int movesToMate = (MateEval - std::abs(res.score) + 1) / 2;
            line.mateSide = res.score > 0 ? std::max(1, movesToMate) : -std::max(1, movesToMate);
            line.cpSide = res.score > 0 ? 10000 : -10000;
        } else {
            line.mateSide = 0;
            line.cpSide = ToCentipawns(res.score, res.ply);
        }

        foundLines.push_back(line);
        gSearch->RootExcludedMoves.push_back(bm);
    }

    gSearch->RootExcludedMoves.clear();

    // Sort lines strictly by rawScore descending so PV1 is always best
    std::sort(foundLines.begin(), foundLines.end(), [](const RawLine& a, const RawLine& b) {
        return a.rawScore > b.rawScore;
    });

    out_result->line_count = static_cast<int32_t>(foundLines.size());
    out_result->depth = foundLines.empty() ? 0 : foundLines[0].depth;

    for (size_t i = 0; i < foundLines.size() && i < 3; ++i) {
        const auto& src = foundLines[i];
        auto& dst = out_result->lines[i];
        dst.score_cp_side = src.cpSide;
        dst.mate_side = src.mateSide;
        dst.depth = src.depth;

        const std::string bmStr = src.bestMove.ToString(false);
        std::strncpy(dst.best_move_uci, bmStr.c_str(), sizeof(dst.best_move_uci) - 1);

        std::string pvJoined;
        for (size_t k = 0; k < src.pv.size() && k < 12; ++k) {
            if (k > 0) pvJoined += ' ';
            pvJoined += src.pv[k].ToString(false);
        }
        std::strncpy(dst.pv_uci, pvJoined.c_str(), sizeof(dst.pv_uci) - 1);
    }

    return true;
}
