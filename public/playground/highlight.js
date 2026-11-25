// Colours qlang code: the same word lists and class names (`tk-*`) as the server-side highlighter of the site.
const words = (text) => new Set(text.split(' '));
const CONTROL = words('if then elseif else end while for in step do break continue match case return');
const DECL = words('fun struct impl trait enum let const');
const MODIFIER = words('public private protected static override extends import export from as');
const OPERATOR_WORDS = words('and or not mod');
const ATOMS = words('true false none self super');
const TYPES = words('int float bool string uuid ulid array map range');

const escapeHtml = (t) => t.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
const span = (kind, text) => `<span class="tk-${kind}">${escapeHtml(text)}</span>`;
const isWordStart = (c) => /[A-Za-z_]/.test(c);
const isWordChar = (c) => /[A-Za-z0-9_]/.test(c);

function classify(word, previous) {
  if (CONTROL.has(word)) return 'control';
  if (DECL.has(word)) return 'decl';
  if (MODIFIER.has(word)) return 'modifier';
  if (OPERATOR_WORDS.has(word)) return 'opword';
  if (ATOMS.has(word)) return 'atom';
  if (TYPES.has(word)) return 'type';
  if (previous === 'fun') return 'fndef';
  if (['struct', 'enum', 'trait', 'extends'].includes(previous)) return 'typedef';
  if (/^[A-Z]/.test(word)) return 'type';
  return 'name';
}

export function highlight(code) {
  let out = '';
  let previous = '';
  let i = 0;
  const n = code.length;
  while (i < n) {
    const c = code[i];
    const start = i;
    if (c === '-' && code[i + 1] === '-') {
      if (code[i + 2] === '"') {
        const close = code.indexOf('--"', i + 3);
        i = close < 0 ? n : close + 3;
        out += span('doc', code.slice(start, i));
      } else {
        while (i < n && code[i] !== '\n') i++;
        out += span('comment', code.slice(start, i));
      }
      previous = '';
    } else if (c === '"') {
      i++;
      while (i < n && code[i] !== '"') i += code[i] === '\\' ? 2 : 1;
      i = Math.min(n, i + 1);
      out += span('string', code.slice(start, i));
      previous = '';
    } else if (/[0-9]/.test(c)) {
      while (i < n && /[0-9._]/.test(code[i])) i++;
      out += span('number', code.slice(start, i));
      previous = '';
    } else if (isWordStart(c)) {
      while (i < n && isWordChar(code[i])) i++;
      const word = code.slice(start, i);
      let kind = classify(word, previous);
      if (kind === 'name' && code[i] === '(') kind = 'fn';
      out += span(kind, word);
      previous = word;
    } else if (c === ' ' || c === '\n' || c === '\t') {
      out += c;
      i++;
    } else {
      out += span('punct', c);
      i++;
      previous = '';
    }
  }
  return out;
}
