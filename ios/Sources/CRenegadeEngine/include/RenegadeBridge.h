#ifndef RENEGADE_BRIDGE_H
#define RENEGADE_BRIDGE_H

#include <stdbool.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct {
    int32_t score_cp_side;     // Normalized centipawns from side-to-move perspective
    int32_t mate_side;         // Non-zero moves to mate from side-to-move (+ winning, - losing), 0 if not mate
    int32_t depth;
    char best_move_uci[8];
    char pv_uci[256];          // Space-separated UCI moves
} RenegadeLineResult;

typedef struct {
    int32_t line_count;
    int32_t depth;
    bool turn_is_white;
    bool is_terminal;
    bool is_checkmate;
    RenegadeLineResult lines[3];
} RenegadeAnalysisResult;

/// Initializes Renegade's lookup tables, TT (hash_mb MB), and mmaps the NNUE weights file.
/// Returns true on success. Safe to call multiple times.
bool renegade_init(const char* network_path, int32_t hash_mb);

/// Clears the transposition table and search histories.
void renegade_clear_hash(void);

/// Signals the active search matching `request_id` (or all requests up to `request_id`) to abort promptly.
void renegade_abort_request(uint64_t request_id);

/// Runs a synchronous MultiPV (1..3) search on `fen` with depth & movetime limits.
/// Returns true if the position was parsed and analyzed.
bool renegade_analyze(
    const char* fen,
    int32_t max_depth,
    int32_t multi_pv,
    int32_t max_time_ms,
    uint64_t request_id,
    RenegadeAnalysisResult* out_result
);

#ifdef __cplusplus
}
#endif

#endif // RENEGADE_BRIDGE_H
