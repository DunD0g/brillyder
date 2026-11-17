import fs from 'node:fs';
import path from 'node:path';
import zlib from 'node:zlib';
import { fileURLToPath } from 'node:url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const rootDir = path.resolve(__dirname, '..');
const publicDir = path.join(rootDir, 'public');
const stockfishBinDir = path.join(rootDir, 'node_modules', 'stockfish', 'bin');

fs.mkdirSync(publicDir, { recursive: true });

function prepareStockfish() {
  if (!fs.existsSync(stockfishBinDir)) {
    console.warn('[prepare-assets] node_modules/stockfish/bin not found yet.');
    return;
  }
  const files = fs.readdirSync(stockfishBinDir);
  const jsCandidate =
    files.find((f) => /stockfish-.*lite-single\.js$/i.test(f)) ||
    files.find((f) => /stockfish-.*-single\.js$/i.test(f));
  const wasmCandidate =
    files.find((f) => /stockfish-.*lite-single\.wasm$/i.test(f)) ||
    files.find((f) => /stockfish-.*-single\.wasm$/i.test(f));

  if (!jsCandidate || !wasmCandidate) {
    console.warn('[prepare-assets] Single-threaded Stockfish build not found.');
    return;
  }

  fs.copyFileSync(path.join(stockfishBinDir, wasmCandidate), path.join(publicDir, 'stockfish.wasm'));
  let jsContent = fs.readFileSync(path.join(stockfishBinDir, jsCandidate), 'utf8');
  if (jsContent.includes(wasmCandidate)) {
    jsContent = jsContent.split(wasmCandidate).join('stockfish.wasm');
  }
  fs.writeFileSync(path.join(publicDir, 'stockfish.js'), jsContent, 'utf8');
  console.log(`[prepare-assets] Stockfish ready: ${jsCandidate} -> public/stockfish.js + .wasm`);
}

const crcTable = (() => {
  const t = new Uint32Array(256);
  for (let n = 0; n < 256; n++) {
    let c = n;
    for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
    t[n] = c >>> 0;
  }
  return t;
})();

function crc32(buf) {
  let c = 0xffffffff;
  for (let i = 0; i < buf.length; i++) c = crcTable[(c ^ buf[i]) & 0xff] ^ (c >>> 8);
  return (c ^ 0xffffffff) >>> 0;
}

function pngChunk(type, data) {
  const len = Buffer.alloc(4);
  len.writeUInt32BE(data.length, 0);
  const tBuf = Buffer.from(type, 'ascii');
  const cBuf = Buffer.alloc(4);
  cBuf.writeUInt32BE(crc32(Buffer.concat([tBuf, data])), 0);
  return Buffer.concat([len, tBuf, data, cBuf]);
}

function createBrillyDerPng(size) {
  const stride = size * 4 + 1;
  const raw = Buffer.alloc(stride * size);
  const setPx = (x, y, r, g, b, a = 255) => {
    if (x < 0 || y < 0 || x >= size || y >= size) return;
    const idx = y * stride + 1 + x * 4;
    const sA = a / 255;
    const dA = raw[idx + 3] / 255;
    const oA = sA + dA * (1 - sA);
    if (oA <= 0) return;
    raw[idx] = Math.round((r * sA + raw[idx] * dA * (1 - sA)) / oA);
    raw[idx + 1] = Math.round((g * sA + raw[idx + 1] * dA * (1 - sA)) / oA);
    raw[idx + 2] = Math.round((b * sA + raw[idx + 2] * dA * (1 - sA)) / oA);
    raw[idx + 3] = Math.round(oA * 255);
  };

  const radius = size * 0.22;
  for (let y = 0; y < size; y++) {
    raw[y * stride] = 0;
    for (let x = 0; x < size; x++) {
      const dx = Math.max(0, Math.abs(x - (size - 1) / 2) - ((size - 1) / 2 - radius));
      const dy = Math.max(0, Math.abs(y - (size - 1) / 2) - ((size - 1) / 2 - radius));
      if (Math.hypot(dx, dy) <= radius) setPx(x, y, 15, 23, 42, 255);
    }
  }

  for (let y = 0; y < size; y++) {
    for (let x = 0; x < size; x++) {
      const u = (x / size - 0.5) * 2;
      const v = (y / size - 0.5) * 2;
      const d = Math.hypot(u, v);
      if (d < 0.72 && d > 0.65) {
        if (u < 0) setPx(x, y, 6, 182, 212, 165);
        else setPx(x, y, 244, 63, 94, 165);
      }
      const inBase = v > 0.34 && v < 0.48 && Math.abs(u) < 0.36;
      const inNeck = v >= 0.05 && v <= 0.34 && Math.abs(u) < 0.26 - (0.34 - v) * 0.25;
      const inCrown = v >= -0.34 && v < 0.05 && Math.abs(u) < 0.34 && (Math.abs(u) < 0.1 || Math.abs(u) > 0.17 || v > -0.14);
      const inTip = Math.hypot(u, v + 0.41) < 0.08 || Math.hypot(u - 0.28, v + 0.32) < 0.07 || Math.hypot(u + 0.28, v + 0.32) < 0.07;
      if (inBase || inNeck || inCrown || inTip) {
        if (u < -0.02) setPx(x, y, 34, 211, 238, 255);
        else if (u > 0.02) setPx(x, y, 251, 113, 133, 255);
        else setPx(x, y, 248, 250, 252, 255);
      }
    }
  }

  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(size, 0);
  ihdr.writeUInt32BE(size, 4);
  ihdr[8] = 8;
  ihdr[9] = 6;
  const compressed = zlib.deflateSync(raw, { level: 9 });
  return Buffer.concat([
    Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]),
    pngChunk('IHDR', ihdr),
    pngChunk('IDAT', compressed),
    pngChunk('IEND', Buffer.alloc(0)),
  ]);
}

function prepareIcons() {
  for (const { file, size } of [
    { file: 'apple-touch-icon.png', size: 180 },
    { file: 'icon-192.png', size: 192 },
    { file: 'icon-512.png', size: 512 },
  ]) {
    const out = path.join(publicDir, file);
    if (!fs.existsSync(out)) {
      fs.writeFileSync(out, createBrillyDerPng(size));
      console.log(`[prepare-assets] Generated public/${file}`);
    }
  }
}

prepareStockfish();
prepareIcons();
