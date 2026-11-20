import type { AnalyzedGame, BrillyVaultEntry, BrillyVaultStats } from '../types/chess';
import { getMoverWinPercent } from '../utils/chessMath';
import { resolveUserColor, resultForUser } from '../utils/player';

function positionKey(fen: string): string {
  return fen.split(' ').slice(0, 4).join(' ');
}

export function buildBrillyVault(
  games: AnalyzedGame[],
  username = ''
): { entries: BrillyVaultEntry[]; stats: BrillyVaultStats } {
  const entries: BrillyVaultEntry[] = [];
  let clutchSaves = 0;
  let trapsPunished = 0;
  let cleanSweeps = 0;

  for (const analyzed of games) {
    const userColor = resolveUserColor(analyzed.game, username);
    const userResult = resultForUser(analyzed.game, userColor);
    const userSummary = userColor === 'w' ? analyzed.whiteSummary : analyzed.blackSummary;
    const seenPositions = new Set<string>();
    const openingName = analyzed.openingLineDetected || analyzed.game.openingName || 'Unknown Opening';

    for (let i = 0; i < analyzed.plies.length; i++) {
      const ply = analyzed.plies[i];
      const key = positionKey(ply.afterFen);
      const repeated = seenPositions.has(key);
      seenPositions.add(key);

      const isUserMove = ply.color === userColor;
      const playerName = ply.color === 'w' ? analyzed.game.white.name : analyzed.game.black.name;
      const opponentName = ply.color === 'w' ? analyzed.game.black.name : analyzed.game.white.name;

      // 1. !! Brilliant moves (existing behavior preserved)
      if (ply.classification === 'brilliant' && !repeated) {
        entries.push({
          id: `br_${analyzed.id}_${ply.ply}`,
          category: 'brilliant',
          gameId: analyzed.id,
          ply: ply.ply,
          moveNumber: ply.moveNumber,
          san: ply.san,
          uci: ply.uci,
          from: ply.from,
          to: ply.to,
          beforeFen: ply.beforeFen,
          afterFen: ply.afterFen,
          color: ply.color,
          playerName,
          opponentName,
          isUserMove,
          openingName,
          openingEco: analyzed.game.openingEco,
          playedAt: analyzed.game.createdAt,
          analyzedAt: analyzed.analyzedAt,
          captured: ply.captured,
          badgeText: '!!',
          reason: ply.coaching.headline,
        });
      }

      if (!isUserMove) continue;

      // 2. Clutch Saves (critical only-move found under pressure)
      const moverWinBefore = getMoverWinPercent(ply.evalBefore, ply.color);
      const inferredClutch =
        ply.isClutchSave ||
        (ply.winLoss <= 2 &&
          ply.classification !== 'book' &&
          moverWinBefore <= 62 &&
          ((ply.secondBestGapPawns ?? 0) >= 2.0 || ply.secondBestGapWin >= 14));

      if (inferredClutch && !repeated) {
        clutchSaves++;
        entries.push({
          id: `cl_${analyzed.id}_${ply.ply}`,
          category: 'clutch',
          gameId: analyzed.id,
          ply: ply.ply,
          moveNumber: ply.moveNumber,
          san: ply.san,
          uci: ply.uci,
          from: ply.from,
          to: ply.to,
          beforeFen: ply.beforeFen,
          afterFen: ply.afterFen,
          color: ply.color,
          playerName,
          opponentName,
          isUserMove: true,
          openingName,
          openingEco: analyzed.game.openingEco,
          playedAt: analyzed.game.createdAt,
          analyzedAt: analyzed.analyzedAt,
          captured: ply.captured,
          badgeText: 'CLUTCH',
          reason: ply.secondBestGapPawns
            ? `Only move (+${ply.secondBestGapPawns.toFixed(1)} gap over 2nd best)`
            : 'Found the only defensive/tactical resource under pressure',
        });
      }

      // 3. Traps Punished (opponent blundered/erred in opening/early middlegame and user punished cleanly)
      if (i > 0 && ply.ply <= 34) {
        const prevOpp = analyzed.plies[i - 1];
        const oppBlundered =
          prevOpp.color !== userColor &&
          (prevOpp.classification === 'blunder' || (prevOpp.classification === 'mistake' && prevOpp.winLoss >= 20));
        const userPunished =
          ply.winLoss <= 2 &&
          (ply.classification === 'best' || ply.classification === 'great' || ply.classification === 'brilliant');

        if (oppBlundered && userPunished) {
          trapsPunished++;
          entries.push({
            id: `tr_${analyzed.id}_${ply.ply}`,
            category: 'traps',
            gameId: analyzed.id,
            ply: ply.ply,
            moveNumber: ply.moveNumber,
            san: ply.san,
            uci: ply.uci,
            from: ply.from,
            to: ply.to,
            beforeFen: ply.beforeFen,
            afterFen: ply.afterFen,
            color: ply.color,
            playerName,
            opponentName,
            isUserMove: true,
            openingName,
            openingEco: analyzed.game.openingEco,
            playedAt: analyzed.game.createdAt,
            analyzedAt: analyzed.analyzedAt,
            captured: ply.captured,
            badgeText: 'PUNISHED',
            reason: `Refuted opponent's ${prevOpp.san} with ${ply.san} (${ply.evalAfter.display})`,
          });
        }
      }
    }

    // 4. Clean Sweeps (blunder-free user win with >= 82% accuracy)
    if (
      userResult === 'W' &&
      userSummary.counts.blunder === 0 &&
      userSummary.accuracy >= 82 &&
      analyzed.plies.length >= 10
    ) {
      const finalPly = analyzed.plies[analyzed.plies.length - 1];
      const playerName = userColor === 'w' ? analyzed.game.white.name : analyzed.game.black.name;
      const opponentName = userColor === 'w' ? analyzed.game.black.name : analyzed.game.white.name;
      cleanSweeps++;
      entries.push({
        id: `cs_${analyzed.id}`,
        category: 'clean',
        gameId: analyzed.id,
        ply: finalPly.ply,
        moveNumber: finalPly.moveNumber,
        san: finalPly.san,
        uci: finalPly.uci,
        from: finalPly.from,
        to: finalPly.to,
        beforeFen: finalPly.beforeFen,
        afterFen: finalPly.afterFen,
        color: userColor,
        playerName,
        opponentName,
        isUserMove: true,
        openingName,
        openingEco: analyzed.game.openingEco,
        playedAt: analyzed.game.createdAt,
        analyzedAt: analyzed.analyzedAt,
        badgeText: `${userSummary.accuracy.toFixed(0)}%`,
        reason: `${userSummary.accuracy.toFixed(1)}% accuracy · 0 blunders · ${analyzed.game.timeControlLabel}`,
      });
    }
  }

  entries.sort((a, b) => b.playedAt - a.playedAt);

  const brilliantEntries = entries.filter((e) => e.category === 'brilliant');
  const openingCounts = new Map<string, number>();
  const userOpeningCounts = new Map<string, number>();
  const monthCounts = new Map<string, { label: string; count: number }>();
  let userMoves = 0;
  let opponentMoves = 0;
  let thisMonth = 0;
  const monthStart = new Date();
  monthStart.setDate(1);
  monthStart.setHours(0, 0, 0, 0);

  for (const entry of brilliantEntries) {
    openingCounts.set(entry.openingName, (openingCounts.get(entry.openingName) ?? 0) + 1);
    const d = new Date(entry.playedAt);
    const key = `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}`;
    const label = d.toLocaleDateString(undefined, { month: 'short', year: 'numeric' });
    const prev = monthCounts.get(key);
    monthCounts.set(key, { label, count: (prev?.count ?? 0) + 1 });

    if (entry.isUserMove) {
      userMoves++;
      userOpeningCounts.set(entry.openingName, (userOpeningCounts.get(entry.openingName) ?? 0) + 1);
      if (entry.playedAt >= monthStart.getTime()) thisMonth++;
    } else {
      opponentMoves++;
    }
  }

  const topOpenings = Array.from(openingCounts.entries())
    .map(([name, count]) => ({ name, count }))
    .sort((a, b) => b.count - a.count)
    .slice(0, 8);
  const topUserOpening = Array.from(userOpeningCounts.entries())
    .map(([name, count]) => ({ name, count }))
    .sort((a, b) => b.count - a.count)[0] ?? null;
  const topMonths = Array.from(monthCounts.entries())
    .map(([key, value]) => ({ key, ...value }))
    .sort((a, b) => (a.key < b.key ? 1 : -1))
    .slice(0, 8);

  return {
    entries,
    stats: {
      total: userMoves,
      userMoves,
      opponentMoves,
      clutchSaves,
      trapsPunished,
      cleanSweeps,
      thisMonth,
      topOpenings,
      topMonths,
      topUserOpening,
    },
  };
}
