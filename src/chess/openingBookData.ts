export interface OpeningEntry {
  eco: string;
  name: string;
  moves: string[];
  /**
   * Relative popularity used by the offline opening explorer. These are not
   * game counts; they only make the theory-book share bars behave sensibly.
   */
  weight: number;
}

function line(eco: string, name: string, weight: number, moves: string): OpeningEntry {
  return {
    eco,
    name,
    weight,
    moves: moves.trim().split(/\s+/),
  };
}

/**
 * A compact, offline opening book covering the first ~8-14 plies of the
 * openings BrillyDer players actually meet. Every line is legal SAN from the
 * standard starting position. The breadth matters more than depth: a move is
 * only called "off book" when the position is known and the move is not one
 * of the recorded continuations.
 */
export const OPENING_BOOK: OpeningEntry[] = [
  // -------------------------------------------------------------------------
  // 1.e4 e5 — open games
  // -------------------------------------------------------------------------
  line('C50', 'Italian Game: Giuoco Piano', 100, 'e4 e5 Nf3 Nc6 Bc4 Bc5 c3 Nf6 d3 d6 O-O O-O'),
  line('C50', 'Italian Game: Giuoco Pianissimo', 90, 'e4 e5 Nf3 Nc6 Bc4 Bc5 d3 Nf6 c3 d6 O-O O-O'),
  line('C50', 'Italian Game: Main Line', 70, 'e4 e5 Nf3 Nc6 Bc4 Bc5 c3 Nf6 d4 exd4 cxd4 Bb4+ Nc3'),
  line('C51', 'Italian Game: Evans Gambit', 45, 'e4 e5 Nf3 Nc6 Bc4 Bc5 b4 Bxb4 c3 Ba5 d4 exd4 O-O'),
  line('C50', 'Italian Game: Quiet 4.d3', 55, 'e4 e5 Nf3 Nc6 Bc4 Bc5 c3 Qe7 d4 Bb6 O-O Nf6'),
  line('C55', 'Italian Game: Two Knights', 80, 'e4 e5 Nf3 Nc6 Bc4 Nf6 Ng5 d5 exd5 Na5 Bb5+ c6 dxc6 bxc6 Be2 h6'),
  line('C57', 'Italian Game: Fried Liver Attack', 40, 'e4 e5 Nf3 Nc6 Bc4 Nf6 Ng5 d5 exd5 Nxd5 Nxf7 Kxf7 Qf3+ Ke6 Nc3'),
  line('C50', 'Italian Game: 3...Nf6', 50, 'e4 e5 Nf3 Nc6 Bc4 Nf6 d3 Bc5 c3 d6 O-O O-O'),
  line('C44', 'Scotch Game: Classical', 80, 'e4 e5 Nf3 Nc6 d4 exd4 Nxd4 Bc5 Be3 Qf6 c3 Nge7 Bc4'),
  line('C45', 'Scotch Game: Mieses', 55, 'e4 e5 Nf3 Nc6 d4 exd4 Nxd4 Nf6 Nxc6 bxc6 e5 Qe7 Qe2 Nd5'),
  line('C44', 'Scotch Game: Four Knights', 40, 'e4 e5 Nf3 Nc6 Nc3 Nf6 d4 exd4 Nxd4 Bb4 Nxc6 bxc6 Bd3 d5 exd5 cxd5'),
  line('C47', 'Four Knights Game: Spanish', 65, 'e4 e5 Nf3 Nc6 Nc3 Nf6 Bb5 Bb4 O-O O-O d3 d6 Bg5 Bxc3 bxc3 Qe7'),
  line('C84', 'Ruy Lopez: Closed', 95, 'e4 e5 Nf3 Nc6 Bb5 a6 Ba4 Nf6 O-O Be7 Re1 b5 Bb3 d6 c3 O-O h3'),
  line('C80', 'Ruy Lopez: Open', 55, 'e4 e5 Nf3 Nc6 Bb5 a6 Ba4 Nf6 O-O Nxe4 d4 b5 Bb3 d5 dxe5 Be6'),
  line('C65', 'Ruy Lopez: Berlin Defense', 85, 'e4 e5 Nf3 Nc6 Bb5 Nf6 O-O Nxe4 d4 Nd6 Bxc6 dxc6 dxe5 Nf5 Qxd8+ Kxd8'),
  line('C68', 'Ruy Lopez: Exchange', 55, 'e4 e5 Nf3 Nc6 Bb5 a6 Bxc6 dxc6 O-O f6 d4 exd4 Nxd4'),
  line('C64', 'Ruy Lopez: Classical', 45, 'e4 e5 Nf3 Nc6 Bb5 Bc5 c3 Nf6 d4 exd4 cxd4 Bb4+'),
  line('C60', 'Ruy Lopez: 3...Nf6', 40, 'e4 e5 Nf3 Nc6 Bb5 Nf6 d3 Bc5 c3 O-O'),
  line('C42', 'Petrov Defense: Classical', 80, 'e4 e5 Nf3 Nf6 Nxe5 d6 Nf3 Nxe4 d4 d5 Bd3 Nc6 O-O Be7 c4'),
  line('C42', 'Petrov Defense: Nimzowitsch', 55, 'e4 e5 Nf3 Nf6 Nxe5 d6 Nf3 Nxe4 Nc3 Nxc3 dxc3 Be7'),
  line('C42', 'Petrov Defense: Main Line', 50, 'e4 e5 Nf3 Nf6 Nxe5 d6 Nf3 Nxe4 d4 d5 Bd3 Nc6 O-O Be7 c4 Nb4'),
  line('C41', 'Philidor Defense', 55, 'e4 e5 Nf3 d6 d4 Nf6 Nc3 Nbd7 Bc4 Be7 O-O O-O'),
  line('C30', 'King\'s Gambit: Kieseritzky', 35, 'e4 e5 f4 exf4 Nf3 g5 h4 g4 Ne5 Nf6 d4 d6'),
  line('C33', 'King\'s Gambit: Bishop\'s Gambit', 30, 'e4 e5 f4 exf4 Bc4 Qh4+ Kf1 d5 Bxd5 Nf6'),
  line('C25', 'Vienna Game', 40, 'e4 e5 Nc3 Nf6 f4 d5 fxe5 Nxe4 Nf3 Be7 d4 O-O Bd3 f5'),
  line('C23', 'Bishop\'s Opening', 40, 'e4 e5 Bc4 Nf6 d3 c6 Nf3 d5 Bb3 Bd6 O-O O-O'),
  line('C21', 'Center Game', 25, 'e4 e5 d4 exd4 Qxd4 Nc6 Qe3 Nf6 Nc3 Bb4 Bd2 O-O'),
  line('C21', 'Danish Gambit', 30, 'e4 e5 d4 exd4 c3 dxc3 Bc4 cxb2 Bxb2 d5 Bxd5 Nf6'),
  line('C44', 'Ponziani Opening', 35, 'e4 e5 Nf3 Nc6 c3 Nf6 d4 Nxe4 Bd3 d5 Nxe5 Nxe5 dxe5 Bc5'),

  // -------------------------------------------------------------------------
  // 1.e4 c5 — Sicilian
  // -------------------------------------------------------------------------
  line('B90', 'Sicilian: Najdorf', 100, 'e4 c5 Nf3 d6 d4 cxd4 Nxd4 Nf6 Nc3 a6 Be3 e5 Nb3 Be6 f3 Be7 Qd2 O-O'),
  line('B90', 'Sicilian: Najdorf, English Attack', 90, 'e4 c5 Nf3 d6 d4 cxd4 Nxd4 Nf6 Nc3 a6 f3 e5 Nb3 Be6 Qd2 Be7'),
  line('B90', 'Sicilian: Najdorf, English Attack Be3', 80, 'e4 c5 Nf3 d6 d4 cxd4 Nxd4 Nf6 Nc3 a6 Be3 e5 Nb3 Be6 f3 Be7 Qd2 O-O O-O-O Nbd7'),
  line('B90', 'Sicilian: Najdorf, Bg5', 80, 'e4 c5 Nf3 d6 d4 cxd4 Nxd4 Nf6 Nc3 a6 Bg5 e6 f4 Be7 Qf3 Qc7 O-O-O Nbd7'),
  line('B90', 'Sicilian: Najdorf, Be2', 65, 'e4 c5 Nf3 d6 d4 cxd4 Nxd4 Nf6 Nc3 a6 Be2 e5 Nb3 Be7 O-O O-O'),
  line('B90', 'Sicilian: Najdorf, Bc4', 50, 'e4 c5 Nf3 d6 d4 cxd4 Nxd4 Nf6 Nc3 a6 Bc4 e6 Bb3 b5 O-O Be7'),
  line('B70', 'Sicilian: Dragon', 80, 'e4 c5 Nf3 d6 d4 cxd4 Nxd4 Nf6 Nc3 g6 Be3 Bg7 f3 O-O Qd2 Nc6 O-O-O d5'),
  line('B70', 'Sicilian: Dragon, Bc4', 55, 'e4 c5 Nf3 d6 d4 cxd4 Nxd4 Nf6 Nc3 g6 Be3 Bg7 Bc4 O-O f3 Nc6 Qd2'),
  line('B56', 'Sicilian: Classical', 75, 'e4 c5 Nf3 d6 d4 cxd4 Nxd4 Nf6 Nc3 Nc6 Bg5 e6 Qd2 Be7 O-O-O O-O'),
  line('B80', 'Sicilian: Scheveningen', 70, 'e4 c5 Nf3 d6 d4 cxd4 Nxd4 Nf6 Nc3 e6 Be2 Be7 O-O O-O f4 Nc6 Be3'),
  line('B33', 'Sicilian: Sveshnikov', 80, 'e4 c5 Nf3 Nc6 d4 cxd4 Nxd4 Nf6 Nc3 e5 Ndb5 d6 Bg5 a6 Na3 b5 Nd5 Be7 Bxf6 Bxf6 c3 O-O'),
  line('B32', 'Sicilian: Löwenthal', 45, 'e4 c5 Nf3 Nc6 d4 cxd4 Nxd4 e5 Nb5 d6 N1c3 a6 Na3 Be7'),
  line('B47', 'Sicilian: Taimanov', 65, 'e4 c5 Nf3 e6 d4 cxd4 Nxd4 Nc6 Nc3 Qc7 Be3 a6 Be2 Nf6 O-O Bb4'),
  line('B42', 'Sicilian: Kan', 55, 'e4 c5 Nf3 e6 d4 cxd4 Nxd4 a6 Bd3 Nf6 O-O Qc7 Qe2 d6 c4'),
  line('B52', 'Sicilian: Moscow Variation', 70, 'e4 c5 Nf3 d6 Bb5+ Nd7 d4 cxd4 Qxd4 a6 Bxd7+ Bxd7 Nc3 Nf6 Bg5 e6 O-O-O Be7'),
  line('B31', 'Sicilian: Rossolimo', 60, 'e4 c5 Nf3 Nc6 Bb5 g6 Bxc6 dxc6 d3 Bg7 h3 Nf6 Nc3 O-O'),
  line('B23', 'Sicilian: Closed', 55, 'e4 c5 Nc3 Nc6 g3 g6 Bg2 Bg7 d3 d6 f4 e6 Nf3 Nge7 O-O O-O'),
  line('B23', 'Sicilian: Grand Prix Attack', 45, 'e4 c5 Nc3 Nc6 f4 g6 Nf3 Bg7 Bc4 e6 f5 Nge7 fxe6 fxe6'),
  line('B22', 'Sicilian: Alapin', 75, 'e4 c5 c3 Nf6 e5 Nd5 d4 cxd4 Nf3 Nc6 cxd4 d6 Bc4 Nb6 Bb5'),
  line('B22', 'Sicilian: Alapin, 2...d5', 55, 'e4 c5 c3 d5 exd5 Qxd5 d4 Nf6 Nf3 Bg4 Be2 e6 O-O Nc6'),
  line('B21', 'Sicilian: Smith-Morra Gambit', 40, 'e4 c5 d4 cxd4 c3 dxc3 Nxc3 Nc6 Nf3 d6 Bc4 e6 O-O Nf6'),

  // -------------------------------------------------------------------------
  // 1.e4 e6 — French
  // -------------------------------------------------------------------------
  line('C02', 'French Defense: Advance', 80, 'e4 e6 d4 d5 e5 c5 c3 Nc6 Nf3 Qb6 a3 Nh6 b4 cxd4'),
  line('C02', 'French Defense: Advance, Bd7', 55, 'e4 e6 d4 d5 e5 c5 c3 Nc6 Nf3 Bd7 Be2 Nge7 O-O Ng6'),
  line('C11', 'French Defense: Classical', 80, 'e4 e6 d4 d5 Nc3 Nf6 Bg5 dxe4 Nxe4 Be7 Bxf6 Bxf6 Nf3 O-O'),
  line('C11', 'French Defense: Classical, Steinitz', 55, 'e4 e6 d4 d5 Nc3 Nf6 Bg5 Be7 e5 Nfd7 Bxe7 Qxe7 f4 O-O Nf3 c5'),
  line('C15', 'French Defense: Winawer', 85, 'e4 e6 d4 d5 Nc3 Bb4 e5 c5 a3 Bxc3+ bxc3 Ne7 Qg4 Qc7 Qxg7 Rg8 Qxh7 cxd4'),
  line('C15', 'French Defense: Winawer, Main Line', 65, 'e4 e6 d4 d5 Nc3 Bb4 e5 c5 a3 Bxc3+ bxc3 Ne7 Nf3 Nbc6'),
  line('C03', 'French Defense: Tarrasch', 70, 'e4 e6 d4 d5 Nd2 Nf6 e5 Nfd7 Bd3 c5 c3 Nc6 Ne2 cxd4 cxd4 f6'),
  line('C01', 'French Defense: Exchange', 45, 'e4 e6 d4 d5 exd5 exd5 Nf3 Nf6 Bd3 Bd6 O-O O-O Bg5 Bg4'),
  line('C10', 'French Defense: Rubinstein', 50, 'e4 e6 d4 d5 Nc3 dxe4 Nxe4 Nd7 Nf3 Ngf6 Nxf6+ Nxf6 Bd3 c5 dxc5 Bxc5'),

  // -------------------------------------------------------------------------
  // 1.e4 c6 — Caro-Kann
  // -------------------------------------------------------------------------
  line('B12', 'Caro-Kann: Advance', 90, 'e4 c6 d4 d5 e5 Bf5 Nf3 e6 Be2 c5 Be3 Qb6 Nc3 Nc6'),
  line('B12', 'Caro-Kann: Advance, Short Castle', 60, 'e4 c6 d4 d5 e5 Bf5 Nf3 e6 Be2 c5 O-O Nc6 c4'),
  line('B18', 'Caro-Kann: Classical', 85, 'e4 c6 d4 d5 Nc3 dxe4 Nxe4 Bf5 Ng3 Bg6 h4 h6 Nf3 Nd7 h5 Bh7 Bd3 Bxd3 Qxd3 e6'),
  line('B18', 'Caro-Kann: Classical, 4...Nd7', 55, 'e4 c6 d4 d5 Nc3 dxe4 Nxe4 Nd7 Bc4 Ngf6 Ng5 e6 Qe2 Nb6 Bb3 h6'),
  line('B13', 'Caro-Kann: Exchange', 60, 'e4 c6 d4 d5 exd5 cxd5 Bd3 Nc6 c3 Nf6 Bf4 Bg4 Qb3 Qd7'),
  line('B13', 'Caro-Kann: Panov Attack', 65, 'e4 c6 d4 d5 exd5 cxd5 c4 Nf6 Nc3 e6 Nf3 Be7 cxd5 Nxd5'),
  line('B10', 'Caro-Kann: Two Knights', 50, 'e4 c6 Nc3 d5 Nf3 Bg4 h3 Bxf3 Qxf3 e6 d3 Nf6 g3 Bb4'),
  line('B12', 'Caro-Kann: Fantasy Variation', 35, 'e4 c6 d4 d5 f3 e6 Nc3 Bb4 Bd2 Ne7 Qe2 O-O'),

  // -------------------------------------------------------------------------
  // 1.e4 d5 — Scandinavian
  // -------------------------------------------------------------------------
  line('B01', 'Scandinavian Defense: Main Line', 65, 'e4 d5 exd5 Qxd5 Nc3 Qa5 d4 Nf6 Nf3 c6 Bc4 Bf5 Bd2 e6'),
  line('B01', 'Scandinavian Defense: 3...Qd6', 50, 'e4 d5 exd5 Qxd5 Nc3 Qd6 d4 Nf6 Nf3 a6 g3 Bg4'),
  line('B01', 'Scandinavian Defense: 2...Nf6', 60, 'e4 d5 exd5 Nf6 d4 Nxd5 Nf3 g6 c4 Nb6 Nc3 Bg7'),
  line('B01', 'Scandinavian Defense: 3.c4', 35, 'e4 d5 exd5 Nf6 c4 e6 dxe6 Bxe6 Nf3 Bd6'),
  line('B01', 'Scandinavian Defense: Icelandic', 40, 'e4 d5 exd5 Qxd5 Nc3 Qa5 d4 Nf6 Nf3 c6 Bc4 Bf5 Bd2 e6 Qe2 Bb4'),

  // -------------------------------------------------------------------------
  // 1.e4 d6 / 1.e4 g6 — Pirc & Modern
  // -------------------------------------------------------------------------
  line('B09', 'Pirc Defense: Austrian Attack', 65, 'e4 d6 d4 Nf6 Nc3 g6 f4 Bg7 Nf3 c5 dxc5 Qa5'),
  line('B08', 'Pirc Defense: Classical', 70, 'e4 d6 d4 Nf6 Nc3 g6 Nf3 Bg7 Be2 O-O O-O c6 a4 Nbd7'),
  line('B07', 'Pirc Defense: 150 Attack', 55, 'e4 d6 d4 Nf6 Nc3 g6 Be3 Bg7 Qd2 c6 f3 b5 Nge2 Nbd7'),
  line('B06', 'Pirc Defense: Lion', 30, 'e4 d6 d4 Nf6 Nc3 c6 f4 Qa5 Bd3 e5 dxe5 dxe5'),
  line('B06', 'Modern Defense: Standard', 60, 'e4 g6 d4 Bg7 Nc3 d6 f4 Nf6 Nf3 O-O Bd3 Nc6'),
  line('B06', 'Modern Defense: 150 Attack', 50, 'e4 g6 d4 Bg7 Nc3 d6 Be3 a6 Qd2 b5 f3 Nd7'),
  line('B06', 'Modern Defense: Gurgenidze', 40, 'e4 g6 d4 Bg7 Nc3 c6 f4 d5 e5 h5'),
  line('B06', 'Modern Defense: Pterodactyl', 30, 'e4 g6 d4 Bg7 Nc3 c5 dxc5 Qa5'),
  line('B06', 'Modern Defense: 2.Nc3', 55, 'e4 g6 Nc3 Bg7 Nf3 d6 d4 Nf6 Be2 O-O O-O'),
  line('B06', 'Modern Defense: 2.Nf3', 50, 'e4 g6 Nf3 Bg7 d4 d6 Nc3 Nf6 Be2 O-O O-O'),
  line('B06', 'Modern Defense: Austrian Attack', 45, 'e4 g6 d4 Bg7 e5 d6 exd6 cxd6 Nf3 Nd7 Bc4 Ngf6'),
  line('B06', 'Modern Defense: 3.Bd3', 40, 'e4 g6 d4 Bg7 Nf3 d6 Bd3 Nd7 O-O Ngf6 h3 b6'),
  line('B06', 'Modern Defense: 3.g3', 35, 'e4 g6 d4 Bg7 Nf3 d6 g3 Bg4 Bg2 Nf6 Nc3 Nc6'),
  line('B06', 'Modern Defense: 3.c3', 30, 'e4 g6 Nf3 Bg7 c3 d6 Bc4 Bg4 O-O Nc6'),
  line('B06', 'Modern Defense: 3.d3', 30, 'e4 g6 Nc3 Bg7 d3 d6 Bd2 Nd7 Nf3 Ne5'),
  line('B06', 'Modern Defense: 4.Ng5', 25, 'e4 g6 Nf3 Bg7 d4 d6 Ng5 Bh6 d5 e5 Nc3 Bxg5'),
  line('B06', 'Modern Defense: Bc4 setup', 30, 'e4 g6 Nf3 Bg7 Bc4 d6 c3 e6 d4 Nd7 Bg5 Ngf6 O-O O-O'),
  line('A40', 'Modern Defense vs d4', 40, 'd4 g6 c4 Bg7 Nc3 d6 e4 Nc6'),

  // -------------------------------------------------------------------------
  // 1.e4 Nf6 — Alekhine
  // -------------------------------------------------------------------------
  line('B04', 'Alekhine Defense: Modern', 55, 'e4 Nf6 e5 Nd5 d4 d6 Nf3 dxe5 Nxe5 c6 Be2 Bf5 O-O Nd7'),
  line('B03', 'Alekhine Defense: Four Pawns Attack', 50, 'e4 Nf6 e5 Nd5 d4 d6 c4 Nb6 f4 dxe5 fxe5 Nc6 Be3 Bf5'),
  line('B03', 'Alekhine Defense: Exchange', 35, 'e4 Nf6 e5 Nd5 d4 d6 c4 Nb6 exd6 cxd6 Nc3 g6 Be3 Bg7'),
  line('B02', 'Alekhine Defense: Two Pawns', 30, 'e4 Nf6 e5 Nd5 c4 Nb6 d4 d6 f4 dxe5 fxe5 Nc6'),
  line('B04', 'Alekhine Defense: 2.Nc3', 25, 'e4 Nf6 Nc3 d5 d4 dxe4 Nxe4'),

  // -------------------------------------------------------------------------
  // 1.d4 d5 — closed games
  // -------------------------------------------------------------------------
  line('D37', 'Queen\'s Gambit Declined: Main Line', 100, 'd4 d5 c4 e6 Nc3 Nf6 Bg5 Be7 e3 O-O Nf3 h6 Bh4 b6'),
  line('D35', 'Queen\'s Gambit Declined: Exchange', 65, 'd4 d5 c4 e6 Nc3 Nf6 cxd5 exd5 Bg5 c6 e3 Bf5 Bd3 Bxd3 Qxd3'),
  line('D20', 'Queen\'s Gambit Accepted: Classical', 75, 'd4 d5 c4 dxc4 Nf3 Nf6 e3 e6 Bxc4 c5 O-O a6 dxc5 Qxd1 Rxd1 Bxc5'),
  line('D20', 'Queen\'s Gambit Accepted: 3.e3', 55, 'd4 d5 c4 dxc4 e3 Nf6 Bxc4 e6 Nf3 c5 O-O a6 dxc5 Qxd1'),
  line('D10', 'Slav Defense: Main Line', 90, 'd4 d5 c4 c6 Nf3 Nf6 Nc3 dxc4 a4 Bf5 e3 e6 Bxc4 Bb4 O-O Nbd7'),
  line('D43', 'Semi-Slav Defense: Main Line', 80, 'd4 d5 c4 c6 Nc3 Nf6 Nf3 e6 Bg5 h6 Bh4 dxc4 e4 g5 Bg3 b5'),
  line('D48', 'Semi-Slav Defense: Meran', 70, 'd4 d5 c4 c6 Nc3 Nf6 e3 e6 Nf3 Nbd7 Bd3 dxc4 Bxc4 b5'),
  line('D43', 'Semi-Slav Defense: Botvinnik', 55, 'd4 d5 c4 c6 Nc3 Nf6 Bg5 e6 e4 h6 Bh4 dxe4 Nxe4 Bb4+'),
  line('D40', 'Tarrasch Defense', 60, 'd4 d5 c4 e6 Nc3 c5 cxd5 exd5 Nf3 Nc6 g3 Nf6 Bg2 Be7 O-O O-O'),
  line('D07', 'Chigorin Defense', 30, 'd4 d5 c4 Nc6 Nf3 Bg4 cxd5 Bxf3 gxf3 Qxd5 e3 e5 Nc3 Bb4'),
  line('D06', 'Baltic Defense', 25, 'd4 d5 c4 Bf5 Nc3 e6 Nf3 c6 Qb3 Qb6 cxd5 Qxb3 axb3 exd5'),
  line('D00', 'Blackmar-Diemer Gambit', 25, 'd4 d5 e4 dxe4 Nc3 Nf6 f3 exf3 Nxf3 g6 Bc4 Bg7 O-O O-O'),
  line('D02', 'London System: 2...Bf5', 45, 'd4 d5 Bf4 Bf5 e3 e6 Nf3 Nf6 c4 c6'),
  line('D02', 'London System: 2...Bf5, Nc3', 35, 'd4 d5 Bf4 Bf5 e3 e6 Nc3 c6 Nf3 Bd6 Bg3 Bxg3 hxg3 h6 Nh4 Bh7 Qe2 Nd7 O-O-O Ngf6'),
  line('D02', 'London System: Main Line', 95, 'd4 d5 Bf4 Nf6 e3 e6 Nf3 c5 c3 Nc6 Nbd2 Bd6 Bg3 O-O'),
  line('D02', 'London System vs c5', 65, 'd4 d5 Bf4 c5 e3 Nc6 c3 Nf6 Nd2 Bf5 Ngf3 e6'),
  line('D02', 'London System: Nf3 First', 70, 'd4 d5 Nf3 Nf6 Bf4 e6 e3 c5 c3 Nc6 Nbd2 Bd6 Bg3 O-O'),
  line('D02', 'London System: Jobava', 55, 'd4 d5 Nc3 Nf6 Bf4 e6 e3 Bb4 Nge2 O-O'),
  line('D04', 'London System vs Indian', 60, 'd4 Nf6 Bf4 g6 e3 Bg7 Nf3 O-O Be2 d6'),
  line('D02', 'London System vs Indian, c5', 50, 'd4 Nf6 Bf4 e6 e3 c5 c3 b6 Nd2 Bb7'),
  line('D02', 'London System vs d5', 55, 'd4 Nf6 Bf4 d5 e3 e6 Nf3 c5 c3 Nc6'),
  line('D02', 'London System: 2.Bf4', 60, 'd4 d5 Bf4 Nf6 e3 c5 c3 Nc6 Nd2 e6'),
  line('D02', 'London System: Nc3 setup', 45, 'd4 d5 Bf4 Nf6 e3 c5 Nc3 Nc6 Nf3 e6 Bd3 Bd6 O-O O-O'),
  line('D02', 'London System via e6', 50, 'd4 e6 Bf4 d5 e3 Nf6 Nf3 c5 c3 Nc6 Nbd2 Bd6 Bg3 O-O'),
  line('D02', 'London System via e6, h3', 45, 'd4 e6 Bf4 d5 e3 Nf6 h3 c5 c3 Nc6 Nd2 Bd6 Ngf3 O-O'),
  line('D02', 'London System vs Horwitz c5', 40, 'd4 e6 Bf4 c5 e3 Nc6 c3 Nf6 Nf3 d5 Nbd2 Bd6 Bg3 O-O'),
  line('D02', 'London System vs Horwitz c5, h3', 30, 'd4 e6 Bf4 c5 e3 Nc6 c3 Nf6 Nf3 d5 h3 h6 Nbd2 a6 Bd3 c4'),
  line('D02', 'London System via Caro-Kann', 40, 'd4 c6 Bf4 d5 e3 Nf6 c3 Bf5 Nd2 e6 Ngf3 Be7 h3 O-O'),
  line('D02', 'London System via Caro, Nf3', 30, 'd4 c6 Bf4 d5 e3 Nf6 Nf3 e6 c3 Be7 Nbd2 O-O'),
  line('A45', 'London System vs Modern g6', 40, 'd4 g6 Bf4 Bg7 e3 d6 Nf3 Nd7 Be2 e5'),
  line('A45', 'London System vs Pirc d6', 35, 'd4 Nf6 Bf4 d6 e3 Nc6 c3 e5 dxe5 Nxe5 Bxe5 dxe5 Qxd8+ Kxd8 Nf3'),
  line('D02', 'London System via d5 e6', 35, 'd4 d5 Bf4 e6 e3 Nf6 Nf3 c5 c3 Nc6 Nbd2 Bd6 Bg3 O-O'),
  line('D05', 'Colle System', 45, 'd4 d5 Nf3 Nf6 e3 e6 Bd3 c5 b3 Nc6 Bb2 Bd6 O-O O-O'),
  line('D10', 'Albin Countergambit', 20, 'd4 d5 c4 e5 dxe5 d4 Nf3 Nc6 e3 Bg4 exd4 Bxf3 Qxf3 Nxd4'),
  line('D41', 'Semi-Tarrasch Defense', 45, 'd4 d5 c4 e6 Nc3 Nf6 Nf3 c5 cxd5 Nxd5 e3 Nc6 Bd3 Be7 O-O O-O'),

  // -------------------------------------------------------------------------
  // 1.d4 Nf6 — Indian defenses
  // -------------------------------------------------------------------------
  line('E20', 'Nimzo-Indian Defense: Main Line', 85, 'd4 Nf6 c4 e6 Nc3 Bb4 e3 O-O Bd3 d5 Nf3 c5 O-O Nc6 a3 Bxc3 bxc3 dxc4 Bxc4 Qc7'),
  line('E20', 'Nimzo-Indian Defense: Qc2', 65, 'd4 Nf6 c4 e6 Nc3 Bb4 Qc2 O-O a3 Bxc3+ Qxc3 b6 Bg5 Bb7 f3 h6'),
  line('E20', 'Nimzo-Indian Defense: Sämisch', 55, 'd4 Nf6 c4 e6 Nc3 Bb4 f3 d5 a3 Bxc3+ bxc3 c5 e3 O-O'),
  line('E15', 'Queen\'s Indian Defense', 70, 'd4 Nf6 c4 e6 Nf3 b6 g3 Bb7 Bg2 Be7 O-O O-O Nc3 Ne4 Qc2 Nxc3'),
  line('E11', 'Bogo-Indian Defense', 45, 'd4 Nf6 c4 e6 Nf3 Bb4+ Bd2 Qe7 g3 O-O Bg2 Bxd2+ Qxd2 d6 O-O e5'),
  line('E60', 'King\'s Indian Defense: Main Line', 90, 'd4 Nf6 c4 g6 Nc3 Bg7 e4 d6 Nf3 O-O Be2 e5 O-O Nc6 d5 Ne7'),
  line('E80', 'King\'s Indian Defense: Sämisch', 70, 'd4 Nf6 c4 g6 Nc3 Bg7 e4 d6 f3 O-O Be3 e5 d5 Nh5 Qd2 f5'),
  line('E76', 'King\'s Indian Defense: Four Pawns Attack', 50, 'd4 Nf6 c4 g6 Nc3 Bg7 e4 d6 f4 O-O Nf3 c5 d5 e6 Be2 exd5'),
  line('E60', 'King\'s Indian Defense: Fianchetto', 55, 'd4 Nf6 c4 g6 Nf3 Bg7 g3 O-O Bg2 d6 O-O Nbd7 Nc3 e5 e4 c6'),
  line('D80', 'Grünfeld Defense: Main Line', 80, 'd4 Nf6 c4 g6 Nc3 d5 cxd5 Nxd5 e4 Nxc3 bxc3 Bg7 Bc4 c5 Ne2 Nc6 Be3 O-O'),
  line('D85', 'Grünfeld Defense: Exchange', 55, 'd4 Nf6 c4 g6 Nc3 d5 cxd5 Nxd5 e4 Nxc3 bxc3 Bg7 Bc4 c5 Ne2 O-O O-O Nc6'),
  line('A60', 'Benoni Defense', 55, 'd4 Nf6 c4 c5 d5 e6 Nc3 exd5 cxd5 d6 e4 g6 Nf3 Bg7 Be2 O-O'),
  line('A57', 'Benko Gambit', 40, 'd4 Nf6 c4 c5 d5 b5 cxb5 a6 bxa6 Bxa6 Nc3 d6 e4 Bxf1 Kxf1 g6'),
  line('A84', 'Dutch Defense: Stonewall', 40, 'd4 f5 g3 Nf6 Bg2 e6 Nf3 Be7 O-O O-O c4 d6 Nc3 Qe8'),
  line('A87', 'Dutch Defense: Leningrad', 45, 'd4 f5 g3 Nf6 Bg2 g6 Nf3 Bg7 O-O O-O c4 d6 Nc3 Qe8'),
  line('A80', 'Dutch Defense: 2.c4', 35, 'd4 f5 c4 Nf6 Nc3 e6 Nf3 Be7 g3 O-O Bg2 d6 O-O Qe8'),
  line('A80', 'Dutch Defense via e6', 30, 'd4 e6 c4 f5 g3 Nf6 Bg2 Be7 Nf3 O-O O-O d6'),
  line('E01', 'Catalan Opening: Closed', 55, 'd4 Nf6 c4 e6 g3 d5 Bg2 Be7 Nf3 O-O O-O dxc4 Qc2 a6'),
  line('E01', 'Catalan Opening: Open', 35, 'd4 Nf6 c4 e6 g3 d5 Bg2 dxc4 Nf3 Be7 O-O O-O Qc2 a6'),
  line('A43', 'Benoni Defense: c5 First', 30, 'd4 c5 d5 e6 Nc3 exd5 Nxd5 Nf6 Nf3 d6'),

  // -------------------------------------------------------------------------
  // 1.c4 — English
  // -------------------------------------------------------------------------
  line('A20', 'English Opening: Reversed Sicilian', 60, 'c4 e5 Nc3 Nf6 Nf3 Nc6 g3 d5 cxd5 Nxd5 Bg2 Nb6 O-O Be7 d3 O-O'),
  line('A29', 'English Opening: Four Knights', 45, 'c4 e5 Nc3 Nf6 Nf3 Nc6 d4 exd4 Nxd4 Bb4 Bg5 h6 Bh4 Bxc3+ bxc3 Qe7'),
  line('A28', 'English Opening: Botvinnik System', 40, 'c4 e5 Nc3 Nc6 g3 g6 Bg2 Bg7 d3 d6 e4 Be6 Nge2 Qd7'),
  line('A30', 'English Opening: Symmetrical', 55, 'c4 c5 Nf3 Nf6 Nc3 Nc6 g3 g6 Bg2 Bg7 O-O O-O d4 cxd4 Nxd4'),
  line('A30', 'English Opening: Symmetrical, Nc3 First', 40, 'c4 c5 Nc3 Nc6 g3 g6 Bg2 Bg7 Nf3 Nf6 O-O O-O d4 cxd4 Nxd4'),
  line('A13', 'English Opening: Anglo-Indian', 45, 'c4 Nf6 Nc3 e6 Nf3 d5 d4 Be7 Bf4 O-O e3 c5 dxc5 Bxc5'),
  line('A19', 'English Opening: Mikenas Attack', 30, 'c4 Nf6 Nc3 e6 e4 d5 e5 d4 exf6 dxc3 bxc3 Qxf6'),
  line('A13', 'English Opening: QGD Transposition', 40, 'c4 e6 Nc3 d5 d4 Nf6 Nf3 Be7 Bg5 O-O e3 h6'),
  line('A10', 'English Opening: Dutch Transposition', 25, 'c4 f5 Nc3 Nf6 g3 e6 Bg2 Be7 Nf3 O-O O-O d6'),

  // -------------------------------------------------------------------------
  // 1.Nf3 — Réti & King's Indian Attack
  // -------------------------------------------------------------------------
  line('A09', 'Réti Opening: Main Line', 55, 'Nf3 d5 c4 e6 g3 Nf6 Bg2 Be7 O-O O-O b3 c5 Bb2 Nc6'),
  line('A09', 'Réti Opening: 2...c6', 40, 'Nf3 d5 c4 c6 b3 Nf6 Bb2 Bf5 g3 e6 Bg2 Be7'),
  line('A07', 'King\'s Indian Attack', 55, 'Nf3 d5 g3 Nf6 Bg2 e6 O-O Be7 d3 O-O Nbd2 c5 e4 Nc6'),
  line('A07', 'King\'s Indian Attack: 2...c6', 35, 'Nf3 d5 g3 Nf6 Bg2 c6 O-O Bg4 d3 Nbd7 Nbd2 e5'),
  line('A13', 'Réti: QGD Transposition', 45, 'Nf3 Nf6 c4 e6 Nc3 d5 d4 Be7 Bf4 O-O e3 c5'),
  line('A07', 'King\'s Indian Attack: 2...Nf6', 30, 'Nf3 Nf6 g3 d5 Bg2 c6 O-O Bg4 d3 Nbd7'),
  line('A20', 'English via Nf3', 40, 'Nf3 c5 c4 Nc6 Nc3 g6 g3 Bg7 Bg2 e6 O-O Nge7'),
  line('A06', 'Nimzo-Larsen Attack', 25, 'Nf3 c5 b3 Nc6 Bb2 d5 e3 Nf6 Bb5 Bd7'),

  // -------------------------------------------------------------------------
  // 1.g3 / 1.b3 / 1.f4 / 1.d3 / 1.c3 / 1.Nc3 — flank openings
  // -------------------------------------------------------------------------
  line('A00', 'King\'s Fianchetto Opening', 35, 'g3 d5 Bg2 e5 d3 Nf6 Nf3 Nc6 O-O Be7 c4 O-O Nc3 d4'),
  line('A00', 'King\'s Fianchetto vs c5', 25, 'g3 c5 Bg2 Nc6 Nf3 g6 O-O Bg7 d3 d6 e4 e6'),
  line('A01', 'Nimzo-Larsen Attack: Main Line', 30, 'b3 e5 Bb2 Nc6 e3 Nf6 Bb5 Bd6 Nf3 Qe7 c4 O-O'),
  line('A01', 'Nimzo-Larsen Attack: vs d5', 25, 'b3 d5 Bb2 Nf6 e3 c5 Nf3 Nc6 Bb5 Bd7 O-O e6'),
  line('A02', 'Bird Opening', 25, 'f4 d5 Nf3 Nf6 e3 g6 Be2 Bg7 O-O O-O d3 c5'),
  line('A02', 'Bird Opening: From\'s Gambit', 15, 'f4 e5 fxe5 d6 exd6 Bxd6 Nf3 g5 d4 g4'),
  line('A00', 'King\'s Indian Attack: d3', 20, 'd3 e5 Nf3 Nc6 g3 d5 Bg2 Nf6 O-O Be7'),
  line('A00', 'Saragossa Opening', 15, 'c3 e5 d4 exd4 cxd4 d5 Nc3 Nf6 Bg5 Be7'),
  line('A00', 'Dunst Opening', 15, 'Nc3 d5 e4 dxe4 Nxe4 e5'),
  line('A45', 'London System vs Indian, g6', 45, 'd4 Nf6 Bf4 g6 e3 Bg7 Nf3 O-O Be2 d6 h3'),
];

export interface OpeningFamily {
  eco: string;
  name: string;
  moves: string[];
}

function family(eco: string, name: string, moves: string): OpeningFamily {
  return { eco, name, moves: moves.trim().split(/\s+/) };
}

/**
 * Short, human-friendly names for the moves shown in the explorer. The deep
 * book entries above are useful for detection but too specific for a 1.e4 or
 * 1...c5 row, so family names win until a more specific family is reached.
 */
export const OPENING_FAMILIES: OpeningFamily[] = [
  family('B00', "King's Pawn Opening", 'e4'),
  family('C20', 'Open Game', 'e4 e5'),
  family('C40', "King's Knight Opening", 'e4 e5 Nf3'),
  family('C50', 'Italian Game', 'e4 e5 Nf3 Nc6 Bc4'),
  family('C55', 'Italian: Two Knights', 'e4 e5 Nf3 Nc6 Bc4 Nf6'),
  family('C51', 'Italian: Evans Gambit', 'e4 e5 Nf3 Nc6 Bc4 Bc5 b4'),
  family('C60', 'Ruy Lopez', 'e4 e5 Nf3 Nc6 Bb5'),
  family('C44', 'Scotch Game', 'e4 e5 Nf3 Nc6 d4'),
  family('C47', 'Four Knights Game', 'e4 e5 Nf3 Nc6 Nc3'),
  family('C42', 'Petrov Defense', 'e4 e5 Nf3 Nf6'),
  family('C41', 'Philidor Defense', 'e4 e5 Nf3 d6'),
  family('C30', "King's Gambit", 'e4 e5 f4'),
  family('C25', 'Vienna Game', 'e4 e5 Nc3'),
  family('C23', "Bishop's Opening", 'e4 e5 Bc4'),
  family('C21', 'Center Game', 'e4 e5 d4'),
  family('B20', 'Sicilian Defense', 'e4 c5'),
  family('B30', 'Sicilian: Old Sicilian', 'e4 c5 Nf3 Nc6'),
  family('B40', 'Sicilian: French Variation', 'e4 c5 Nf3 e6'),
  family('B50', 'Sicilian: Open', 'e4 c5 Nf3 d6 d4 cxd4 Nxd4'),
  family('B90', 'Sicilian: Najdorf', 'e4 c5 Nf3 d6 d4 cxd4 Nxd4 Nf6 Nc3 a6'),
  family('B70', 'Sicilian: Dragon', 'e4 c5 Nf3 d6 d4 cxd4 Nxd4 Nf6 Nc3 g6'),
  family('B56', 'Sicilian: Classical', 'e4 c5 Nf3 d6 d4 cxd4 Nxd4 Nf6 Nc3 Nc6'),
  family('B80', 'Sicilian: Scheveningen', 'e4 c5 Nf3 d6 d4 cxd4 Nxd4 Nf6 Nc3 e6'),
  family('B33', 'Sicilian: Sveshnikov', 'e4 c5 Nf3 Nc6 d4 cxd4 Nxd4 Nf6 Nc3 e5'),
  family('B22', 'Sicilian: Alapin', 'e4 c5 c3'),
  family('B23', 'Sicilian: Closed', 'e4 c5 Nc3'),
  family('B31', 'Sicilian: Rossolimo', 'e4 c5 Nf3 Nc6 Bb5'),
  family('B52', 'Sicilian: Moscow', 'e4 c5 Nf3 d6 Bb5+'),
  family('C00', 'French Defense', 'e4 e6'),
  family('C02', 'French: Advance', 'e4 e6 d4 d5 e5'),
  family('C15', 'French: Winawer', 'e4 e6 d4 d5 Nc3 Bb4'),
  family('C10', 'French: Classical', 'e4 e6 d4 d5 Nc3 Nf6'),
  family('C03', 'French: Tarrasch', 'e4 e6 d4 d5 Nd2'),
  family('B10', 'Caro-Kann Defense', 'e4 c6'),
  family('B12', 'Caro-Kann: Advance', 'e4 c6 d4 d5 e5'),
  family('B18', 'Caro-Kann: Classical', 'e4 c6 d4 d5 Nc3 dxe4 Nxe4 Bf5'),
  family('B01', 'Scandinavian Defense', 'e4 d5'),
  family('B07', 'Pirc Defense', 'e4 d6'),
  family('B06', 'Modern Defense', 'e4 g6'),
  family('B02', 'Alekhine Defense', 'e4 Nf6'),
  family('A40', "Queen's Pawn Opening", 'd4'),
  family('D00', "Queen's Pawn Game", 'd4 d5'),
  family('D02', 'London System', 'd4 d5 Bf4'),
  family('D02', 'London System', 'd4 Nf6 Bf4'),
  family('D02', 'London System', 'd4 e6 Bf4'),
  family('D02', 'London System', 'd4 c6 Bf4'),
  family('D02', 'London System', 'd4 g6 Bf4'),
  family('D02', 'London System', 'd4 Nf6 Bf4 d6'),
  family('D06', "Queen's Gambit", 'd4 d5 c4'),
  family('D20', "Queen's Gambit Accepted", 'd4 d5 c4 dxc4'),
  family('D30', "Queen's Gambit Declined", 'd4 d5 c4 e6'),
  family('D10', 'Slav Defense', 'd4 d5 c4 c6'),
  family('D40', 'Tarrasch Defense', 'd4 d5 c4 e6 Nc3 c5'),
  family('D07', 'Chigorin Defense', 'd4 d5 c4 Nc6'),
  family('D06', 'Baltic Defense', 'd4 d5 c4 Bf5'),
  family('A45', 'Indian Defense', 'd4 Nf6'),
  family('E20', 'Nimzo-Indian Defense', 'd4 Nf6 c4 e6 Nc3 Bb4'),
  family('E15', "Queen's Indian Defense", 'd4 Nf6 c4 e6 Nf3 b6'),
  family('E60', "King's Indian Defense", 'd4 Nf6 c4 g6'),
  family('D80', 'Grünfeld Defense', 'd4 Nf6 c4 g6 Nc3 d5'),
  family('A60', 'Benoni Defense', 'd4 Nf6 c4 c5'),
  family('A57', 'Benko Gambit', 'd4 Nf6 c4 c5 d5 b5'),
  family('A80', 'Dutch Defense', 'd4 f5'),
  family('E01', 'Catalan Opening', 'd4 Nf6 c4 e6 g3'),
  family('A20', 'English Opening', 'c4'),
  family('A20', 'English: Reversed Sicilian', 'c4 e5'),
  family('A30', 'English: Symmetrical', 'c4 c5'),
  family('A09', 'Réti Opening', 'Nf3'),
  family('A09', 'Réti Opening', 'Nf3 d5 c4'),
  family('A07', "King's Indian Attack", 'Nf3 d5 g3'),
  family('A45', 'Indian Defense', 'Nf3 Nf6'),
  family('A00', "King's Fianchetto Opening", 'g3'),
  family('A01', 'Nimzo-Larsen Attack', 'b3'),
  family('A02', 'Bird Opening', 'f4'),
  family('A00', 'Saragossa Opening', 'c3'),
  family('A00', 'Dunst Opening', 'Nc3'),
  family('A00', "King's Indian Attack", 'd3'),
];
