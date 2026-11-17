import type { AnalyzedGame, BrillyVaultEntry, BrillyVaultStats } from '../types/chess';
import { resolveUserColor } from '../utils/player';

function positionKey(fen: string): string {
  return fen.split(' ').slice(0, 4).join(' ');
}

export function buildBrillyVault(games: AnalyzedGame[], username = ''): { entries: BrillyVaultEntry[]; stats: BrillyVaultStats } {
  const entries: BrillyVaultEntry[] = [];

  for (const analyzed of games) {
    const userColor = resolveUserColor(analyzed.game, username);
    const seenPositions = new Set<string>();
    for (const ply of analyzed.plies) {
      const key = positionKey(ply.afterFen);
      const repeated = seenPositions.has(key);
      seenPositions.add(key);
      if (ply.classification !== 'brilliant' || repeated) continue;
      const isUserMove = ply.color === userColor;
      const playerName = ply.color === 'w' ? analyzed.game.white.name : analyzed.game.black.name;
      const opponentName = ply.color === 'w' ? analyzed.game.black.name : analyzed.game.white.name;
      entries.push({
        id: `${analyzed.id}_${ply.ply}`,
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
        openingName: analyzed.openingLineDetected || analyzed.game.openingName || 'Unknown Opening',
        openingEco: analyzed.game.openingEco,
        playedAt: analyzed.game.createdAt,
        analyzedAt: analyzed.analyzedAt,
        captured: ply.captured,
      });
    }
  }

  entries.sort((a, b) => b.playedAt - a.playedAt);

  const openingCounts = new Map<string, number>();
  const playerCounts = new Map<string, number>();
  const monthCounts = new Map<string, { label: string; count: number }>();
  let userMoves = 0;
  let opponentMoves = 0;
  let thisMonth = 0;
  const monthStart = new Date();
  monthStart.setDate(1);
  monthStart.setHours(0, 0, 0, 0);

  for (const entry of entries) {
    if (entry.isUserMove) userMoves++; else opponentMoves++;
    if (entry.playedAt >= monthStart.getTime()) thisMonth++;
    openingCounts.set(entry.openingName, (openingCounts.get(entry.openingName) ?? 0) + 1);
    playerCounts.set(entry.playerName, (playerCounts.get(entry.playerName) ?? 0) + 1);
    const d = new Date(entry.playedAt);
    const key = `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}`;
    const label = d.toLocaleDateString(undefined, { month: 'short', year: 'numeric' });
    const prev = monthCounts.get(key);
    monthCounts.set(key, { label, count: (prev?.count ?? 0) + 1 });
  }

  const topOpenings = Array.from(openingCounts.entries())
    .map(([name, count]) => ({ name, count }))
    .sort((a, b) => b.count - a.count)
    .slice(0, 8);
  const topPlayers = Array.from(playerCounts.entries())
    .map(([name, count]) => ({ name, count }))
    .sort((a, b) => b.count - a.count)
    .slice(0, 8);
  const topMonths = Array.from(monthCounts.entries())
    .map(([key, value]) => ({ key, ...value }))
    .sort((a, b) => (a.key < b.key ? 1 : -1))
    .slice(0, 8);

  return {
    entries,
    stats: { total: entries.length, userMoves, opponentMoves, thisMonth, topOpenings, topPlayers, topMonths },
  };
}
