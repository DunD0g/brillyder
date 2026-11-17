import type { MoveClassification } from '../types/chess';

const SOUND_PREF_KEY = 'brillyder_sound_muted';

class SoundEngine {
  private ctx: AudioContext | null = null;
  private muted: boolean;

  constructor() {
    this.muted = localStorage.getItem(SOUND_PREF_KEY) === 'true';
  }

  private ensureContext(): AudioContext | null {
    if (this.muted || typeof window === 'undefined') return null;
    if (!this.ctx) {
      const AudioCtx = window.AudioContext || (window as unknown as { webkitAudioContext: typeof AudioContext }).webkitAudioContext;
      if (!AudioCtx) return null;
      this.ctx = new AudioCtx();
    }
    if (this.ctx.state === 'suspended') this.ctx.resume().catch(() => undefined);
    return this.ctx;
  }

  unlock(): void { this.ensureContext(); }
  isMuted(): boolean { return this.muted; }
  setMuted(next: boolean): void {
    this.muted = next;
    localStorage.setItem(SOUND_PREF_KEY, String(next));
  }

  private tone(freq: number, dur: number, type: OscillatorType = 'sine', peak = 0.12, delay = 0, endFreq?: number): void {
    const ctx = this.ensureContext();
    if (!ctx) return;
    const now = ctx.currentTime + delay;
    const osc = ctx.createOscillator();
    const gain = ctx.createGain();
    osc.type = type;
    osc.frequency.setValueAtTime(freq, now);
    if (endFreq) osc.frequency.exponentialRampToValueAtTime(endFreq, now + dur);
    gain.gain.setValueAtTime(0.0001, now);
    gain.gain.exponentialRampToValueAtTime(peak, now + 0.008);
    gain.gain.exponentialRampToValueAtTime(0.0001, now + dur);
    osc.connect(gain);
    gain.connect(ctx.destination);
    osc.start(now);
    osc.stop(now + dur + 0.02);
  }

  playMove(): void { this.tone(240, 0.06, 'triangle', 0.12, 0, 150); }
  playCapture(): void {
    this.tone(360, 0.075, 'sawtooth', 0.09, 0, 140);
    this.tone(180, 0.05, 'triangle', 0.12, 0.01, 110);
  }
  playCheck(): void { this.tone(520, 0.11, 'sine', 0.13, 0, 390); }
  playSuccess(): void {
    this.tone(523.25, 0.09, 'sine', 0.11, 0);
    this.tone(783.99, 0.15, 'sine', 0.12, 0.08);
  }
  playError(): void { this.tone(190, 0.14, 'triangle', 0.1, 0, 135); }

  playClassification(cls: MoveClassification, isCapture = false, isCheck = false): void {
    if (cls === 'brilliant') {
      this.tone(523.25, 0.12, 'sine', 0.11, 0);
      this.tone(659.25, 0.12, 'sine', 0.11, 0.06);
      this.tone(783.99, 0.18, 'sine', 0.13, 0.12);
      return;
    }
    if (cls === 'great') {
      this.tone(440, 0.1, 'sine', 0.1, 0);
      this.tone(587.33, 0.14, 'sine', 0.11, 0.06);
      return;
    }
    if (cls === 'blunder') {
      this.tone(185, 0.16, 'sawtooth', 0.08, 0, 110);
      this.tone(130, 0.22, 'triangle', 0.1, 0.08, 92);
      return;
    }
    if (cls === 'mistake') { this.tone(220, 0.14, 'triangle', 0.09, 0, 165); return; }
    if (cls === 'inaccuracy') { this.tone(290, 0.09, 'sine', 0.08, 0, 240); return; }
    if (isCheck) this.playCheck();
    else if (isCapture) this.playCapture();
    else this.playMove();
  }
}

export const soundManager = new SoundEngine();
