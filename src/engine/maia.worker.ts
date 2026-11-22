import * as ort from 'onnxruntime-web/wasm';

interface LoadMessage {
  type: 'load';
  id: number;
  modelUrl: string;
  modelKey?: string;
  modelBuffer?: ArrayBuffer;
}

interface InferMessage {
  type: 'infer';
  id: number;
  planes: Float32Array;
  legalMoves: Array<{ uci: string; index: number }>;
}

type WorkerRequest = LoadMessage | InferMessage;

let session: ort.InferenceSession | null = null;
let loadedKey = '';
let queue: Promise<void> = Promise.resolve();

async function handleRequest(msg: WorkerRequest): Promise<void> {
  try {
    if (msg.type === 'load') {
      const key = msg.modelKey || msg.modelUrl;
      if (session && loadedKey === key) {
        self.postMessage({ type: 'loaded', id: msg.id, ok: true });
        return;
      }
      ort.env.wasm.numThreads = 1;
      if (msg.modelBuffer) {
        session = await ort.InferenceSession.create(new Uint8Array(msg.modelBuffer), {
          executionProviders: ['wasm'],
        });
      } else {
        session = await ort.InferenceSession.create(msg.modelUrl, {
          executionProviders: ['wasm'],
        });
      }
      loadedKey = key;
      self.postMessage({ type: 'loaded', id: msg.id, ok: true });
      return;
    }

    if (msg.type === 'infer') {
      if (!session) {
        self.postMessage({ type: 'result', id: msg.id, moveUci: null, error: 'Model not loaded' });
        return;
      }
      const inputName = session.inputNames[0];
      const tensor = new ort.Tensor('float32', msg.planes, [1, 112, 8, 8]);
      const outputMap = await session.run({ [inputName]: tensor });
      const policyName =
        session.outputNames.find((n) => /policy/i.test(n)) ?? session.outputNames[0];
      const policyTensor = outputMap[policyName];
      const logits = policyTensor?.data as Float32Array | undefined;

      if (!logits || msg.legalMoves.length === 0) {
        self.postMessage({ type: 'result', id: msg.id, moveUci: null });
        return;
      }

      let bestUci: string | null = null;
      let bestScore = -Infinity;
      for (const cand of msg.legalMoves) {
        const val = cand.index >= 0 && cand.index < logits.length ? logits[cand.index] : -Infinity;
        if (val > bestScore) {
          bestScore = val;
          bestUci = cand.uci;
        }
      }

      self.postMessage({ type: 'result', id: msg.id, moveUci: bestUci });
    }
  } catch (err) {
    self.postMessage({
      type: 'error',
      id: msg.id,
      error: err instanceof Error ? err.message : 'Maia worker error',
    });
  }
}

self.onmessage = (event: MessageEvent<WorkerRequest>) => {
  const msg = event.data;
  queue = queue.then(() => handleRequest(msg), () => handleRequest(msg));
};
