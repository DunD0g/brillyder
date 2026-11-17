export interface OpeningEntry {
  eco: string;
  name: string;
  moves: string[];
}

const OPENING_BOOK: OpeningEntry[] = [
  { eco: 'D02', name: 'London System', moves: ['d4', 'd5', 'Bf4', 'Nf6', 'e3', 'c5', 'c3', 'Nc6', 'Nd2'] },
  { eco: 'D02', name: 'London System: Jobava', moves: ['d4', 'd5', 'Nc3', 'Nf6', 'Bf4', 'e6', 'e3', 'Bb4'] },
  { eco: 'A45', name: 'London System vs Indian', moves: ['d4', 'Nf6', 'Bf4', 'g6', 'e3', 'Bg7', 'Nf3', 'O-O', 'h3', 'd6'] },
  { eco: 'A45', name: 'London System vs Indian', moves: ['d4', 'Nf6', 'Bf4', 'e6', 'e3', 'c5', 'c3', 'b6', 'Nd2'] },
  { eco: 'B06', name: 'Modern Defense: Standard', moves: ['e4', 'g6', 'd4', 'Bg7', 'Nc3', 'd6', 'Be3', 'a6'] },
  { eco: 'B06', name: 'Modern Defense: Pterodactyl', moves: ['e4', 'g6', 'd4', 'Bg7', 'Nc3', 'c5', 'dxc5', 'Qa5'] },
  { eco: 'B06', name: 'Modern Defense: Gurgenidze', moves: ['e4', 'g6', 'd4', 'Bg7', 'Nc3', 'c6', 'f4', 'd5'] },
  { eco: 'A40', name: 'Modern Defense vs d4', moves: ['d4', 'g6', 'c4', 'Bg7', 'Nc3', 'd6', 'e4', 'Nc6'] },
  { eco: 'B07', name: 'Pirc Defense: Austrian Attack', moves: ['e4', 'd6', 'd4', 'Nf6', 'Nc3', 'g6', 'f4', 'Bg7', 'Nf3', 'O-O'] },
  { eco: 'C50', name: 'Italian Game: Giuoco Piano', moves: ['e4', 'e5', 'Nf3', 'Nc6', 'Bc4', 'Bc5', 'c3', 'Nf6', 'd3', 'd6'] },
  { eco: 'C55', name: 'Italian Game: Two Knights', moves: ['e4', 'e5', 'Nf3', 'Nc6', 'Bc4', 'Nf6', 'Ng5', 'd5', 'exd5', 'Na5'] },
  { eco: 'C84', name: 'Ruy Lopez: Closed', moves: ['e4', 'e5', 'Nf3', 'Nc6', 'Bb5', 'a6', 'Ba4', 'Nf6', 'O-O', 'Be7'] },
  { eco: 'C45', name: 'Scotch Game: Classical', moves: ['e4', 'e5', 'Nf3', 'Nc6', 'd4', 'exd4', 'Nxd4', 'Bc5', 'Be3', 'Qf6'] },
  { eco: 'C42', name: 'Petrov Defense', moves: ['e4', 'e5', 'Nf3', 'Nf6', 'Nxe5', 'd6', 'Nf3', 'Nxe4', 'd4', 'd5'] },
  { eco: 'B21', name: 'Sicilian: Smith-Morra Gambit', moves: ['e4', 'c5', 'd4', 'cxd4', 'c3', 'dxc3', 'Nxc3', 'Nc6'] },
  { eco: 'B22', name: 'Sicilian: Alapin Variation', moves: ['e4', 'c5', 'c3', 'Nf6', 'e5', 'Nd5', 'd4', 'cxd4'] },
  { eco: 'B50', name: 'Sicilian: Open', moves: ['e4', 'c5', 'Nf3', 'd6', 'd4', 'cxd4', 'Nxd4', 'Nf6', 'Nc3'] },
  { eco: 'B90', name: 'Sicilian: Najdorf', moves: ['e4', 'c5', 'Nf3', 'd6', 'd4', 'cxd4', 'Nxd4', 'Nf6', 'Nc3', 'a6', 'Be3', 'e5'] },
  { eco: 'B12', name: 'Caro-Kann: Advance', moves: ['e4', 'c6', 'd4', 'd5', 'e5', 'Bf5', 'Nf3', 'e6', 'Be2', 'c5'] },
  { eco: 'B18', name: 'Caro-Kann: Classical', moves: ['e4', 'c6', 'd4', 'd5', 'Nc3', 'dxe4', 'Nxe4', 'Bf5', 'Ng3', 'Bg6'] },
  { eco: 'C02', name: 'French Defense: Advance', moves: ['e4', 'e6', 'd4', 'd5', 'e5', 'c5', 'c3', 'Nc6', 'Nf3', 'Qb6'] },
  { eco: 'C11', name: 'French Defense: Classical', moves: ['e4', 'e6', 'd4', 'd5', 'Nc3', 'Nf6', 'Bg5', 'dxe4', 'Nxe4', 'Be7'] },
  { eco: 'B01', name: 'Scandinavian Defense', moves: ['e4', 'd5', 'exd5', 'Qxd5', 'Nc3', 'Qa5', 'd4', 'Nf6'] },
  { eco: 'D37', name: 'Queens Gambit Declined', moves: ['d4', 'd5', 'c4', 'e6', 'Nc3', 'Nf6', 'Nf3', 'Be7', 'Bf4', 'O-O'] },
  { eco: 'D10', name: 'Slav Defense', moves: ['d4', 'd5', 'c4', 'c6', 'Nf3', 'Nf6', 'Nc3', 'dxc4', 'a4', 'Bf5'] },
  { eco: 'E20', name: 'Nimzo-Indian Defense', moves: ['d4', 'Nf6', 'c4', 'e6', 'Nc3', 'Bb4', 'e3', 'O-O', 'Bd3', 'd5'] },
  { eco: 'E60', name: 'Kings Indian Defense', moves: ['d4', 'Nf6', 'c4', 'g6', 'Nc3', 'Bg7', 'e4', 'd6', 'Nf3', 'O-O', 'Be2', 'e5'] },
  { eco: 'A20', name: 'English Opening', moves: ['c4', 'e5', 'Nc3', 'Nf6', 'Nf3', 'Nc6', 'g3', 'd5'] },
  { eco: 'A06', name: 'Reti Opening', moves: ['Nf3', 'd5', 'c4', 'd4', 'b4', 'f6', 'e3'] },
];

export function lookupOpeningByMoves(sanHistory: string[]): { matchedPlies: number; eco: string; name: string } | null {
  let best: { matchedPlies: number; eco: string; name: string } | null = null;
  for (const entry of OPENING_BOOK) {
    let matched = 0;
    const limit = Math.min(sanHistory.length, entry.moves.length);
    for (let i = 0; i < limit; i++) {
      if (sanHistory[i] === entry.moves[i]) matched++;
      else break;
    }
    if (matched >= 3 && (!best || matched > best.matchedPlies)) {
      best = { matchedPlies: matched, eco: entry.eco, name: entry.name };
    }
  }
  return best;
}

export function isBookPly(plyIndex: number, sanPrefix: string[], lichessOpeningPly?: number, winLoss = 0): boolean {
  if (plyIndex >= 16 || winLoss > 8) return false;
  const match = lookupOpeningByMoves(sanPrefix);
  if (match && plyIndex < match.matchedPlies) return true;
  if (lichessOpeningPly && plyIndex < Math.min(lichessOpeningPly, 14) && winLoss <= 6) return true;
  return false;
}
