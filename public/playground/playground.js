import { run } from './engine.js';
import { highlight } from './highlight.js';
import { EXAMPLES } from './examples.js';

const $ = (id) => document.getElementById(id);
const source = $('pg-source');
const colored = $('pg-colored');
const output = $('pg-output');
const stdin = $('pg-stdin');
const runButton = $('pg-run');
const examples = $('pg-examples');
const status = $('pg-status');
const labels = JSON.parse($('pg-labels').textContent);

const store = {
  get(key) { try { return localStorage.getItem(key); } catch (e) { return null; } },
  set(key, value) { try { localStorage.setItem(key, value); } catch (e) { /* private mode */ } },
};

const toBase64Url = (text) => {
  const bytes = new TextEncoder().encode(text);
  let binary = '';
  bytes.forEach((b) => { binary += String.fromCharCode(b); });
  return btoa(binary).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
};
const fromBase64Url = (text) => {
  const binary = atob(text.replace(/-/g, '+').replace(/_/g, '/'));
  return new TextDecoder().decode(Uint8Array.from(binary, (c) => c.charCodeAt(0)));
};

function paint() {
  // the trailing newline keeps the last empty line of the textarea visible in the coloured copy
  colored.innerHTML = highlight(source.value) + '\n';
  stdin.hidden = !/\bread\s*\(/.test(source.value);
}

function syncScroll() {
  colored.parentElement.scrollTop = source.scrollTop;
  colored.parentElement.scrollLeft = source.scrollLeft;
}

function setCode(code) {
  source.value = code;
  paint();
  store.set('playground-code', code);
}

function span(cls, text) {
  const s = document.createElement('span');
  if (cls) s.className = cls;
  s.textContent = text;
  return s;
}

function describe(d) {
  const where = d.location ? `${d.location.line}:${d.location.col} ` : '';
  const notes = (d.notes || []).map((n) => `\n  ${n.message}`).join('');
  return `${where}${d.code}: ${d.message}${notes}`;
}

async function execute() {
  runButton.disabled = true;
  status.textContent = labels.running;
  const lines = stdin.hidden || stdin.value === '' ? [] : stdin.value.split('\n');
  const started = performance.now();
  const result = await run({ 'main.q': source.value }, lines);
  runButton.disabled = false;
  status.textContent = '';
  if (result.stopped) {
    if (result.detail) console.error('qlang:', result.detail);
    output.replaceChildren(span('error', labels['stopped_' + result.stopped]));
    return;
  }
  const answer = result.answer;
  const parts = [];
  if (answer.output) parts.push(span('', answer.output));
  for (const d of answer.diagnostics || []) parts.push(span('error', describe(d) + '\n'));
  if (parts.length === 0) parts.push(span('muted', labels.empty));
  output.replaceChildren(...parts);
  status.textContent = `${Math.round(performance.now() - started)} ms`;
}

for (const [index, example] of EXAMPLES.entries()) {
  const option = document.createElement('option');
  option.value = String(index);
  option.textContent = example.name;
  examples.append(option);
}
examples.addEventListener('change', () => {
  if (examples.value !== '') setCode(EXAMPLES[Number(examples.value)].code);
  examples.value = '';
  output.replaceChildren();
});

source.addEventListener('input', () => { paint(); store.set('playground-code', source.value); });
source.addEventListener('scroll', syncScroll);
source.addEventListener('keydown', (event) => {
  if ((event.ctrlKey || event.metaKey) && event.key === 'Enter') {
    event.preventDefault();
    execute();
  } else if (event.key === 'Tab' && !event.shiftKey) {
    event.preventDefault();
    const { selectionStart: a, selectionEnd: b } = source;
    source.setRangeText('    ', a, b, 'end');
    paint();
  }
});
runButton.addEventListener('click', execute);

$('pg-share').addEventListener('click', async () => {
  const url = `${location.origin}${location.pathname}#c=${toBase64Url(source.value)}`;
  history.replaceState(null, '', url);
  try {
    await navigator.clipboard.writeText(url);
    status.textContent = labels.copied;
  } catch (e) {
    status.textContent = labels.copy_failed;
  }
});

$('pg-reset').addEventListener('click', () => { setCode(EXAMPLES[0].code); output.replaceChildren(); history.replaceState(null, '', location.pathname); });

const shared = location.hash.startsWith('#c=') ? location.hash.slice(3) : '';
let initial = null;
if (shared) {
  try { initial = fromBase64Url(shared); } catch (e) { initial = null; }
}
setCode(initial ?? store.get('playground-code') ?? EXAMPLES[0].code);
