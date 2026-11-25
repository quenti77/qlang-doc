// One qlang engine (a Web Worker) for the page. A program that does not end is stopped by killing the worker.
const LIMITS = { timeoutMs: 8000, maxSteps: 20000000, maxDepth: 250 };

let worker = null;
let nextId = 1;
const pending = new Map();

function start() {
  worker = new Worker('/playground/worker.js', { type: 'module' });
  worker.postMessage({ type: 'init', wasmUrl: '/playground/qlang.wasm' });
  worker.onmessage = ({ data }) => {
    const done = pending.get(data.id);
    if (done) {
      pending.delete(data.id);
      done(data);
    }
  };
  worker.onerror = () => {
    for (const done of pending.values()) done({ crash: 'worker error' });
    pending.clear();
    worker = null;
  };
}

/** Runs `files` (entry `main.q`) with the given stdin lines. Resolves to {answer} or {stopped: "timeout" | "crash"}. */
export function run(files, input) {
  if (!worker) start();
  const id = nextId++;
  const [hi, lo] = crypto.getRandomValues(new Uint32Array(2));
  const request = {
    files,
    input,
    now: Date.now(),
    seed: hi * 2 ** 21 + (lo >>> 11),
    limits: { max_steps: LIMITS.maxSteps, max_depth: LIMITS.maxDepth },
  };
  return new Promise((resolve) => {
    const timer = setTimeout(() => {
      pending.delete(id);
      worker.terminate();
      worker = null;
      resolve({ stopped: 'timeout' });
    }, LIMITS.timeoutMs);
    pending.set(id, (data) => {
      clearTimeout(timer);
      if (data.crash) {
        worker.terminate();
        worker = null;
        resolve({ stopped: 'crash', detail: data.crash });
      } else {
        resolve({ answer: data.answer });
      }
    });
    worker.postMessage({ id, request });
  });
}
