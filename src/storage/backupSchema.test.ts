import { describe, expect, it } from 'vitest';
import { validateBackupPayload } from './brillyDb';

describe('IndexedDB JSON backup schema validation', () => {
  it('accepts valid v2 BrillyDer backup payloads', () => {
    const valid = validateBackupPayload({
      app: 'brillyder',
      schemaVersion: 2,
      exportedAt: '2026-01-01T00:00:00.000Z',
      stores: {
        analyzed_games: [],
        prefs: [{ key: 'brillyder_vibe', value: 'cosmic', updatedAt: 1 }],
        repertoires: [],
        fsrs_cards: [],
        woodpecker_cycles: [],
        training_logs: [],
      },
    });
    expect(valid.schemaVersion).toBe(2);
    expect(valid.stores.prefs).toHaveLength(1);
  });

  it('rejects non-BrillyDer or malformed payloads', () => {
    expect(() => validateBackupPayload(null)).toThrow(/JSON object/i);
    expect(() => validateBackupPayload({ app: 'other', schemaVersion: 2, stores: {} })).toThrow(/Unrecognized/i);
    expect(() => validateBackupPayload({ app: 'brillyder', schemaVersion: 99, stores: {} })).toThrow(/Unsupported/i);
    expect(() => validateBackupPayload({
      app: 'brillyder',
      schemaVersion: 2,
      stores: { analyzed_games: 'bad' },
    })).toThrow(/must be an array/i);
  });
});
