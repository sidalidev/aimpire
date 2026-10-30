// Lecture incrémentale des journaux Claude Code (~/.claude/projects/**/*.jsonl), en lecture seule.
// Chaque fichier a un cache { offset, compteurs } : on ne relit que ce qui a été ajouté depuis la dernière fois.
// Les lignes sont filtrées par sous-chaîne avant JSON.parse : 3,8 Go de journaux, il faut rester léger.
import fs from 'node:fs';
import path from 'node:path';
import { CLAUDE_DIR } from './paths.js';
import { DAY, SESSION_MAX_AGE, SUB_MAX_AGE, BUCKET } from './config.js';

export const BASE = path.join(CLAUDE_DIR, 'projects');
export { DAY };

const WOOD = new Set(['Edit', 'Write', 'NotebookEdit', 'MultiEdit']);
const SCROLL = new Set(['Read', 'Grep', 'Glob', 'WebSearch', 'WebFetch', 'LS']);
const BUILD_RE = /\b(npm|pnpm|yarn|bun)\s+(run\s+)?(build|install|ci|lint|typecheck|dev|start)\b|\bnpx?\s+(tsc|eslint|prisma|vite|playwright|electron-builder|cap)\b|\bmake\b|cargo (build|run)|go build|\bmvn\b|\bgradle\w*\b|xcodebuild|docker (build|compose)|prisma (migrate|db|generate)|\bpip3? install|\bpytest\b|\bgit (push|rebase|merge)\b/;
const TEST_RE = /\b(npm|pnpm|yarn|bun)\s+(run\s+)?test\b|playwright test|\bpytest\b|\bvitest\b|\bjest\b|cargo test|go test|mvn test|gradle test/;
const PASS_RE = /(\d+)\s+passed|\bPASS\b|✓|Tests?:\s+\d+ passed|OK \(\d+ tests?\)/;
const FAIL_RE = /\bfailed\b|\bFAIL\b|✗|Error:/;

export function unitOf(model) {
  const m = (model || '').toLowerCase();
  if (!m || m.startsWith('<')) return 'paysan';
  if (m.includes('opus')) return 'chevalier';
  if (m.includes('sonnet')) return 'soldat';
  if (m.includes('haiku')) return 'eclaireur';
  if (m.includes('fable')) return 'mage';
  return 'paysan';
}
export const FOOD_COST = { chevalier: 5, soldat: 1, eclaireur: 0.2, mage: 12, paysan: 0 };

export function emptyTally() {
  return { bois: 0, pierre: 0, parchemins: 0, or: 0, tour: 0, edits: 0, tests: 0, testsOk: 0, commits: 0, linesAdded: 0,
    tools: 0, cost: 0, tokens: 0, days: {} };
}
export const dayKey = (t) => new Date(t).toLocaleDateString('sv');   // jour local, pas UTC
// Compteur du jour (registre durable) : ce qui a été gagné ce jour-là par cette session.
function day(t, ts) {
  const k = dayKey(ts);
  return (t.days[k] ||= { bois: 0, pierre: 0, parchemins: 0, or: 0, commits: 0, tests: 0, testsOk: 0, usd: 0, min: 0 });
}

function textOf(content) {
  if (typeof content === 'string') return content;
  if (Array.isArray(content)) return content.map((b) => (b && b.type === 'text' ? b.text : '')).join(' ');
  return '';
}
const clip = (t, n) => String(t || '').replace(/\s+/g, ' ').trim().slice(0, n);

// Applique une ligne de journal au cache d'un fichier. `food` est le cache global de nourriture (seaux de 10 min).
function applyLine(line, c, food, stats) {
  if (stats && !c.version) { const vm = /"version":"([^"]+)"/.exec(line); if (vm) { c.version = vm[1]; stats.versions[vm[1]] = true; } }
  const tsm = /"timestamp":"([^"]+)"/.exec(line);
  const ts = tsm ? Date.parse(tsm[1]) : (c.last || Date.now());   // les lignes sans horodatage (cost-state) prennent celui de la précédente
  if (tsm && ts) { c.last = Math.max(c.last || 0, ts); c.first = c.first ? Math.min(c.first, ts) : ts; if (stats) stats.lastLineAt = Math.max(stats.lastLineAt, ts); }
  if (!c.cwd) { const m = /"cwd":"([^"]+)"/.exec(line); if (m) c.cwd = m[1]; }
  const gb = /"gitBranch":"([^"]+)"/.exec(line); if (gb) c.branch = gb[1];

  const isAssistant = line.includes('"type":"assistant"');
  const isUser = line.includes('"type":"user"');
  const isSystem = line.includes('"type":"system"');
  // minutes actives : une ligne horodatée dans un seau de 10 min = 10 min de présence ce jour-là (approximation volontaire)
  if (ts && !line.includes('"type":"progress"')) {
    const b = Math.floor(ts / BUCKET);
    if (b !== c.lastBucket) { c.lastBucket = b; day(c.tally ||= emptyTally(), ts).min += 10; }
  }
  // signaux (lignes system) : fin de tour, erreur API, compactage, repli de modèle. Lecture par regex, sans JSON.parse.
  if (isSystem) {
    if (line.includes('"subtype":"turn_duration"')) { c.turnEnd = ts; c.turns = (c.turns || 0) + 1; }
    else if (line.includes('"subtype":"api_error"')) { c.errors = (c.errors || 0) + 1; c.lastError = ts; const r = /"retryAttempt":(\d+)/.exec(line); c.retry = r ? Number(r[1]) : 0; }
    else if (line.includes('"subtype":"compact_boundary"')) { c.compacts = (c.compacts || 0) + 1; c.lastCompact = ts; }
    else if (line.includes('"subtype":"model_refusal_fallback"')) c.fallbacks = (c.fallbacks || 0) + 1;
    return;
  }
  // résultats d'outils : on retire l'outil des « en attente » et on lit la décision de permission, sans JSON.parse
  if (isUser && line.includes('"tool_result"')) {
    c.pending ||= {};
    for (const m of line.matchAll(/"tool_use_id":"([^"]+)"/g)) delete c.pending[m[1]];
    const pd = /"permissionDecision":\{"decision":"([a-z]+)"/.exec(line);
    if (pd) { c.lastPermission = { decision: pd[1], ts }; if (pd[1] !== 'accept') c.denied = (c.denied || 0) + 1; }
    if (line.includes('"toolDenialKind"')) c.denied = (c.denied || 0) + 1;
    if (!c.pendingTest) return;
  }
  const interesting = isAssistant || line.includes('"type":"cost-state"') || line.includes('"type":"ai-title"')
    || line.includes('"type":"custom-title"') || line.includes('"prUrl"') || isUser;
  if (!interesting) return;
  let d; try { d = JSON.parse(line); } catch { if (stats) stats.badLines++; return; }
  const t = c.tally;

  if (d.type === 'ai-title' && d.aiTitle) c.title = clip(d.aiTitle, 40);
  if (d.type === 'custom-title' && d.customTitle) c.customTitle = clip(d.customTitle, 40);
  if (d.prUrl && !c.pr) { c.pr = d.prUrl; t.or += 3; day(t, ts).or += 3; }
  if (d.type === 'cost-state') {
    if (typeof d.totalLinesAdded === 'number') t.linesAdded = Math.max(t.linesAdded, d.totalLinesAdded);
    if (typeof d.totalCostUSD === 'number' && d.totalCostUSD > t.cost) { if (t.cost > 0 || c.offset === 0) day(t, ts).usd += d.totalCostUSD - t.cost; t.cost = d.totalCostUSD; }
    if (d.modelUsage) {
      let tok = 0, usage = {};
      for (const [m, u] of Object.entries(d.modelUsage)) {
        tok += (u.inputTokens || 0) + (u.outputTokens || 0) + (u.cacheCreationInputTokens || 0);
        usage[m] = u.costUSD || 0;
      }
      t.tokens = Math.max(t.tokens, tok); c.usage = usage;
    }
    return;
  }
  const m = d.message;
  if (d.type === 'assistant' && m && typeof m === 'object') {
    if (m.model && !String(m.model).startsWith('<')) c.model = m.model;
    if (d.effort) c.effort = d.effort;
    if (d.quotaLimits) c.quota = { ...d.quotaLimits, ts: ts || Date.now() };
    const content = Array.isArray(m.content) ? m.content : [];
    const dd = day(t, ts);
    for (const b of content) {
      if (!b || b.type !== 'tool_use') continue;
      t.tools++; c.lastTool = b.name; c.lastToolTs = ts; c.sub = !!d.isSidechain;
      const name = b.name || '';
      if (!d.isSidechain && b.id) (c.pending ||= {})[b.id] = { name, ts };
      if (WOOD.has(name)) { t.bois++; t.edits++; dd.bois++; }
      else if (name === 'Bash') {
        const cmd = String(b.input?.command || '');
        if (/\bgit\s+commit\b/.test(cmd)) { t.commits++; t.or++; dd.commits++; dd.or++; }
        if (TEST_RE.test(cmd)) { t.tests++; t.pierre += 2; dd.tests++; dd.pierre += 2; c.pendingTest = b.id; }
        else if (BUILD_RE.test(cmd)) { t.pierre++; dd.pierre++; }
      } else if (SCROLL.has(name)) { t.parchemins++; dd.parchemins++; }
      else if (/^mcp__(claude-in-chrome|Claude_Browser|computer-use|plugin_playwright)/.test(name)) t.tour++;
      else { t.parchemins += 0.5; dd.parchemins += 0.5; }
    }
    const said = textOf(content);
    if (said && !d.isSidechain) c.said = clip(said, 220);
    // nourriture : tokens pondérés par le coût du modèle, dans un seau de 10 min
    if (m.usage && ts) {
      const u = m.usage;
      const weight = FOOD_COST[unitOf(m.model)] || 0;
      const work = (u.output_tokens || 0) * 4 + (u.input_tokens || 0) + (u.cache_creation_input_tokens || 0) + (u.cache_read_input_tokens || 0) * 0.1;
      const key = String(Math.floor(ts / BUCKET) * BUCKET);
      const unit = unitOf(m.model);
      food[key] ||= {};
      food[key][unit] = (food[key][unit] || 0) + work * weight / 1000;
    }
    return;
  }
  if (d.type === 'user' && m) {
    const content = m.content;
    if (Array.isArray(content) && content.some((b) => b && b.type === 'tool_result')) {
      if (c.pendingTest) {
        const r = content.find((b) => b && b.type === 'tool_result' && b.tool_use_id === c.pendingTest);
        if (r) {
          const out = typeof r.content === 'string' ? r.content : textOf(r.content);
          const dd = day(t, ts);
          if (PASS_RE.test(out) && !FAIL_RE.test(out)) { t.or++; t.testsOk++; dd.or++; dd.testsOk++; c.lastTestOk = true; }
          else if (FAIL_RE.test(out)) c.lastTestOk = false;
          c.pendingTest = null;
        }
      }
      return;
    }
    const asked = textOf(content);
    if (asked && !asked.startsWith('<') && !d.isSidechain) { c.asked = clip(asked, 160); c.askedTs = ts; c.pending = {}; if (!c.firstAsk) c.firstAsk = clip(asked, 40); }
  }
}

// Lit ce qui a été ajouté au fichier depuis c.offset. Retourne true si quelque chose a été lu.
// On borne la lecture à la taille vue au stat : si le fichier grandit pendant la lecture, le reste viendra au tour suivant
// (sinon les mêmes lignes seraient comptées deux fois). Le décodage utf8 est fait par le flux pour ne jamais couper un caractère.
export async function scanFile(file, c, food, stats) {
  let st; try { st = fs.statSync(file); } catch { return false; }
  const offset = c.offset || 0;
  if (st.size < offset) Object.assign(c, { offset: 0, tally: emptyTally(), partial: '' });
  if (st.size === (c.offset || 0)) return false;
  c.tally ||= emptyTally();
  const start = c.offset || 0, end = st.size - 1;
  await new Promise((resolve) => {
    const rs = fs.createReadStream(file, { start, end, highWaterMark: 1 << 20 });
    rs.setEncoding('utf8');
    let rest = c.partial || '';
    rs.on('data', (chunk) => {
      const lines = (rest + chunk).split('\n');
      rest = lines.pop();
      for (const l of lines) if (l) applyLine(l, c, food, stats);
    });
    rs.on('end', () => { c.partial = rest.length < (1 << 20) ? rest : ''; c.offset = st.size; resolve(); });
    rs.on('error', (e) => { if (stats) stats.badLines++; c.partial = ''; resolve(); });
  });
  c.mtime = st.mtimeMs;
  return true;
}

// Liste les sessions (fichiers de premier niveau) et les sous-agents récents.
export function listFiles(now = Date.now()) {
  const sessions = [], subs = [];
  let dirs = [];
  try { dirs = fs.readdirSync(BASE); } catch { return { sessions, subs }; }
  for (const dir of dirs) {
    const full = path.join(BASE, dir);
    let items = [];
    try { items = fs.readdirSync(full, { withFileTypes: true }); } catch { continue; }
    for (const it of items) {
      if (!it.isFile() || !it.name.endsWith('.jsonl')) continue;
      const f = path.join(full, it.name);
      let st; try { st = fs.statSync(f); } catch { continue; }
      if (now - st.mtimeMs > SESSION_MAX_AGE) continue;
      sessions.push({ file: f, mtime: st.mtimeMs, id: it.name.slice(0, -6) });
      if (now - st.mtimeMs < SUB_MAX_AGE) {
        const root = path.join(full, it.name.slice(0, -6), 'subagents');
        const walk = (d, depth) => {
          let xs = []; try { xs = fs.readdirSync(d, { withFileTypes: true }); } catch { return; }
          for (const x of xs) {
            const p = path.join(d, x.name);
            if (x.isDirectory() && depth < 3) walk(p, depth + 1);
            else if (x.name.startsWith('agent-') && x.name.endsWith('.jsonl')) {
              let s2; try { s2 = fs.statSync(p); } catch { continue; }
              if (now - s2.mtimeMs < SUB_MAX_AGE) subs.push({ file: p, mtime: s2.mtimeMs, session: f, id: x.name.slice(6, -6), workflow: p.split(path.sep).includes('workflows') });
            }
          }
        };
        walk(root, 0);
      }
    }
  }
  return { sessions, subs };
}

// Registre des sessions vivantes (~/.claude/sessions/<pid>.json) : statut busy/idle en temps réel. Non documenté, donc tolérant.
export function readRegistry() {
  const out = {};
  const dir = path.join(CLAUDE_DIR, 'sessions');
  let xs = []; try { xs = fs.readdirSync(dir); } catch { return out; }
  for (const f of xs) {
    if (!f.endsWith('.json')) continue;
    try {
      const d = JSON.parse(fs.readFileSync(path.join(dir, f), 'utf8'));
      if (d.sessionId) out[d.sessionId] = { status: d.status || '', updatedAt: Number(d.updatedAt) || 0, entrypoint: d.entrypoint || '', remote: !!d.bridgeSessionId, pid: Number(d.pid) || 0 };
    } catch {}
  }
  return out;
}

export function pruneFood(food, now = Date.now()) {
  for (const k of Object.keys(food)) if (now - Number(k) > 8 * DAY) delete food[k];
}
