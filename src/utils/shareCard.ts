import { BOARD_THEME_LIST, BOARD_THEMES } from '../chess/boardThemes';
import type { BoardThemeId, PlayerColor } from '../types/chess';

export interface ShareCardInput {
  title: string;
  subtitle?: string;
  badgeText?: string;
  badgeColor?: string;
  fen: string;
  orientation: PlayerColor;
  lastMove?: [string, string];
  evalText?: string;
  moveText?: string;
  whiteName: string;
  blackName: string;
  footerMeta?: string;
  boardTheme: BoardThemeId;
}

// Use filled chess silhouettes + text presentation selector (\uFE0E) on pawn so white pieces stay opaque
// and iOS Safari never turns black pawns into Apple Color Emojis.
const PIECE_UNICODE: Record<string, string> = {
  K: '♚',
  Q: '♛',
  R: '♜',
  B: '♝',
  N: '♞',
  P: '♟\uFE0E',
  k: '♚',
  q: '♛',
  r: '♜',
  b: '♝',
  n: '♞',
  p: '♟\uFE0E',
};

function fitTextWithEllipsis(ctx: CanvasRenderingContext2D, text: string, maxWidth: number): string {
  if (maxWidth <= 0) return '';
  if (ctx.measureText(text).width <= maxWidth) return text;
  let lo = 0;
  let hi = text.length;
  while (lo < hi) {
    const mid = Math.ceil((lo + hi) / 2);
    const cand = `${text.slice(0, mid)}…`;
    if (ctx.measureText(cand).width <= maxWidth) lo = mid;
    else hi = mid - 1;
  }
  return lo > 0 ? `${text.slice(0, lo)}…` : '…';
}

export function parseFenToBoardMatrix(fen: string): Array<Array<string | null>> {
  const placement = (fen.split(' ')[0] ?? '').split('/');
  const rows: Array<Array<string | null>> = [];
  for (let r = 0; r < 8; r++) {
    const line = placement[r] ?? '8';
    const row: Array<string | null> = [];
    for (const ch of line) {
      if (ch >= '1' && ch <= '8') {
        const count = parseInt(ch, 10);
        for (let i = 0; i < count; i++) row.push(null);
      } else if (PIECE_UNICODE[ch]) {
        row.push(ch);
      }
    }
    while (row.length < 8) row.push(null);
    rows.push(row.slice(0, 8));
  }
  return rows;
}

export function buildShareCardFilename(title: string): string {
  const slug = title
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-|-$/g, '')
    .slice(0, 36);
  return `brillyder-${slug || 'highlight'}.png`;
}

function drawRoundedRect(
  ctx: CanvasRenderingContext2D,
  x: number,
  y: number,
  w: number,
  h: number,
  r: number
): void {
  ctx.beginPath();
  ctx.moveTo(x + r, y);
  ctx.lineTo(x + w - r, y);
  ctx.quadraticCurveTo(x + w, y, x + w, y + r);
  ctx.lineTo(x + w, y + h - r);
  ctx.quadraticCurveTo(x + w, y + h, x + w - r, y + h);
  ctx.lineTo(x + r, y + h);
  ctx.quadraticCurveTo(x, y + h, x, y + h - r);
  ctx.lineTo(x, y + r);
  ctx.quadraticCurveTo(x, y, x + r, y);
  ctx.closePath();
}

function squareToGrid(sq: string, orientation: PlayerColor): { row: number; col: number } | null {
  if (!sq || sq.length < 2) return null;
  const file = sq.charCodeAt(0) - 97;
  const rank = parseInt(sq[1], 10);
  if (file < 0 || file > 7 || !Number.isFinite(rank) || rank < 1 || rank > 8) return null;
  if (orientation === 'w') {
    return { row: 8 - rank, col: file };
  }
  return { row: rank - 1, col: 7 - file };
}

/**
 * Renders a crisp 1080×1350 Cosmic Minimalist highlight PNG card entirely client-side.
 */
export async function renderShareCardBlob(input: ShareCardInput): Promise<Blob> {
  const width = 1080;
  const height = 1350;
  const canvas = document.createElement('canvas');
  canvas.width = width;
  canvas.height = height;
  const ctx = canvas.getContext('2d');
  if (!ctx) throw new Error('Canvas 2D unavailable.');

  // Cosmic Void background + subtle nebula glow
  const bg = ctx.createLinearGradient(0, 0, width, height);
  bg.addColorStop(0, '#070B14');
  bg.addColorStop(0.55, '#0F172A');
  bg.addColorStop(1, '#091020');
  ctx.fillStyle = bg;
  ctx.fillRect(0, 0, width, height);

  const glow1 = ctx.createRadialGradient(900, 140, 20, 900, 140, 420);
  glow1.addColorStop(0, 'rgba(45, 212, 191, 0.22)');
  glow1.addColorStop(1, 'rgba(45, 212, 191, 0)');
  ctx.fillStyle = glow1;
  ctx.fillRect(0, 0, width, height);

  const glow2 = ctx.createRadialGradient(180, 1200, 20, 180, 1200, 420);
  glow2.addColorStop(0, 'rgba(168, 85, 247, 0.18)');
  glow2.addColorStop(1, 'rgba(168, 85, 247, 0)');
  ctx.fillStyle = glow2;
  ctx.fillRect(0, 0, width, height);

  // Outer glass card frame
  drawRoundedRect(ctx, 42, 42, width - 84, height - 84, 36);
  ctx.fillStyle = 'rgba(15, 23, 42, 0.72)';
  ctx.fill();
  ctx.lineWidth = 2;
  ctx.strokeStyle = 'rgba(45, 212, 191, 0.35)';
  ctx.stroke();

  // Header brand + badge
  ctx.font = '900 32px -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif';
  ctx.fillStyle = '#2DD4BF';
  ctx.fillText('BRILLY', 86, 118);
  const brillyW = ctx.measureText('BRILLY').width;
  ctx.fillStyle = '#FB7185';
  ctx.fillText('DER', 86 + brillyW, 118);

  if (input.badgeText) {
    const badgeColor = input.badgeColor || '#2DD4BF';
    ctx.font = '900 24px -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif';
    const textW = ctx.measureText(input.badgeText).width;
    const pillW = textW + 40;
    const pillX = width - 86 - pillW;
    drawRoundedRect(ctx, pillX, 82, pillW, 48, 24);
    ctx.fillStyle = `${badgeColor}28`;
    ctx.fill();
    ctx.strokeStyle = badgeColor;
    ctx.lineWidth = 2;
    ctx.stroke();
    ctx.fillStyle = badgeColor;
    ctx.fillText(input.badgeText, pillX + 20, 114);
  }

  // Title + Move / Eval line (measured cleanly to fit within inner card width)
  const innerMaxW = width - 172;
  ctx.font = '800 42px -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif';
  ctx.fillStyle = '#F8FAFC';
  ctx.fillText(fitTextWithEllipsis(ctx, input.title, innerMaxW), 86, 186);

  if (input.subtitle) {
    ctx.font = '500 24px -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif';
    ctx.fillStyle = '#94A3B8';
    ctx.fillText(fitTextWithEllipsis(ctx, input.subtitle, innerMaxW), 86, 228);
  }

  // Chessboard
  const boardSize = 840;
  const boardX = (width - boardSize) / 2;
  const boardY = 264;
  const sqSize = boardSize / 8;
  const palette = BOARD_THEMES[input.boardTheme] ?? BOARD_THEME_LIST[0];
  const matrix = parseFenToBoardMatrix(input.fen);

  const lastFrom = input.lastMove ? squareToGrid(input.lastMove[0], input.orientation) : null;
  const lastTo = input.lastMove ? squareToGrid(input.lastMove[1], input.orientation) : null;

  ctx.save();
  drawRoundedRect(ctx, boardX, boardY, boardSize, boardSize, 20);
  ctx.clip();

  for (let row = 0; row < 8; row++) {
    for (let col = 0; col < 8; col++) {
      const isLight = (row + col) % 2 === 0;
      const x = boardX + col * sqSize;
      const y = boardY + row * sqSize;
      ctx.fillStyle = isLight ? palette.lightSquare : palette.darkSquare;
      ctx.fillRect(x, y, sqSize, sqSize);

      const isLast =
        (lastFrom && lastFrom.row === row && lastFrom.col === col) ||
        (lastTo && lastTo.row === row && lastTo.col === col);
      if (isLast) {
        ctx.fillStyle = 'rgba(45, 212, 191, 0.36)';
        ctx.fillRect(x, y, sqSize, sqSize);
      }

      const srcRow = input.orientation === 'w' ? row : 7 - row;
      const srcCol = input.orientation === 'w' ? col : 7 - col;
      const piece = matrix[srcRow]?.[srcCol];
      if (piece) {
        const glyph = PIECE_UNICODE[piece];
        const isWhitePiece = piece === piece.toUpperCase();
        ctx.font = `700 ${Math.round(sqSize * 0.74)}px "Apple Symbols", "Segoe UI Symbol", "Noto Sans Symbols 2", serif`;
        ctx.textAlign = 'center';
        ctx.textBaseline = 'middle';
        ctx.lineJoin = 'round';
        ctx.lineWidth = isWhitePiece ? 6 : 4;
        ctx.strokeStyle = isWhitePiece ? '#0F172A' : 'rgba(248, 250, 252, 0.85)';
        ctx.strokeText(glyph, x + sqSize / 2, y + sqSize / 2 + 4);
        ctx.fillStyle = isWhitePiece ? '#FFFFFF' : '#0B1120';
        ctx.fillText(glyph, x + sqSize / 2, y + sqSize / 2 + 4);
      }
    }
  }
  ctx.restore();

  // Board outer border
  drawRoundedRect(ctx, boardX, boardY, boardSize, boardSize, 20);
  ctx.lineWidth = 3;
  ctx.strokeStyle = 'rgba(148, 163, 184, 0.35)';
  ctx.stroke();

  // Reset text alignment
  ctx.textAlign = 'left';
  ctx.textBaseline = 'alphabetic';

  // Footer info strip (reserve right-side width so player names & move/eval never overlap)
  const footY = boardY + boardSize + 58;
  const rightText = [input.moveText, input.evalText].filter(Boolean).join('  ·  ');
  let rightReserved = 0;
  if (rightText) {
    ctx.font = '800 28px ui-monospace, SFMono-Regular, Menlo, monospace';
    ctx.fillStyle = '#2DD4BF';
    const rw = Math.min(380, ctx.measureText(rightText).width);
    const fittedRight = fitTextWithEllipsis(ctx, rightText, 380);
    const actualRw = ctx.measureText(fittedRight).width;
    ctx.fillText(fittedRight, width - 86 - actualRw, footY);
    rightReserved = Math.max(rw, actualRw) + 28;
  }

  ctx.font = '800 30px -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif';
  ctx.fillStyle = '#E2E8F0';
  const playersLine = fitTextWithEllipsis(
    ctx,
    `${input.whiteName} vs ${input.blackName}`,
    innerMaxW - rightReserved
  );
  ctx.fillText(playersLine, 86, footY);

  ctx.font = '600 22px -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif';
  ctx.fillStyle = '#64748B';
  ctx.fillText(
    fitTextWithEllipsis(
      ctx,
      input.footerMeta || 'Analyzed locally on-device with Stockfish WASM · BrillyDer',
      innerMaxW
    ),
    86,
    footY + 46
  );

  return new Promise<Blob>((resolve, reject) => {
    canvas.toBlob((blob) => {
      if (blob) resolve(blob);
      else reject(new Error('Failed to encode PNG card.'));
    }, 'image/png');
  });
}

export async function shareOrDownloadCard(input: ShareCardInput): Promise<'shared' | 'downloaded'> {
  const blob = await renderShareCardBlob(input);
  const filename = buildShareCardFilename(input.title);
  const file = new File([blob], filename, { type: 'image/png' });

  if (
    typeof navigator !== 'undefined' &&
    typeof navigator.share === 'function' &&
    typeof navigator.canShare === 'function' &&
    navigator.canShare({ files: [file] })
  ) {
    try {
      await navigator.share({
        title: input.title,
        text: `${input.whiteName} vs ${input.blackName}${input.moveText ? ` — ${input.moveText}` : ''}`,
        files: [file],
      });
      return 'shared';
    } catch (err) {
      // If user canceled native share sheet, don't force a fallback download
      if (err instanceof DOMException && err.name === 'AbortError') {
        return 'shared';
      }
    }
  }

  const url = URL.createObjectURL(blob);
  const a = document.createElement('a');
  a.href = url;
  a.download = filename;
  document.body.appendChild(a);
  a.click();
  a.remove();
  // Defer revocation so Safari/WebKit finishes reading the blob before cleanup
  window.setTimeout(() => URL.revokeObjectURL(url), 1000);
  return 'downloaded';
}
