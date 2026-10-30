// Bilan du jour et rapport hebdomadaire du Sénat, en Markdown, calculés depuis le registre durable (S.ledger.days).
import { dayKey } from './scan.js';
import { DAY } from './config.js';

const RES_NAMES = { or: 'gold', bois: 'wood', pierre: 'stone', parchemins: 'scrolls', commits: 'commits' };
const fmtMin = (m) => `${Math.floor(m / 60)} h ${String(Math.round(m % 60)).padStart(2, '0')} min`;

export function report(S, periode, now) {
  const days = S.ledger?.days || {};
  const n = periode === 'semaine' ? 7 : 1;
  const keys = [];
  for (let i = 0; i < n; i++) keys.push(dayKey(now - i * DAY));
  const prevKeys = [];
  for (let i = n; i < 2 * n; i++) prevKeys.push(dayKey(now - i * DAY));
  const sum = (ks) => ks.reduce((a, k) => { const d = days[k]; if (!d) return a; for (const r of ['or', 'commits', 'tests', 'testsOk', 'usd', 'min']) a[r] += d[r] || 0; for (const [v, x] of Object.entries(d.villages || {})) { a.villages[v] ||= { min: 0, commits: 0, or: 0 }; a.villages[v].min += x.min; a.villages[v].commits += x.commits; a.villages[v].or += x.or; } return a; }, { or: 0, commits: 0, tests: 0, testsOk: 0, usd: 0, min: 0, villages: {} });
  const cur = sum(keys), prev = sum(prevKeys);
  const delta = (a, b) => (b ? `${a >= b ? '+' : ''}${Math.round((a - b) / b * 100)}%` : '');
  const name = (vid) => (S.villages || []).find((v) => v.id === vid)?.name || vid.split('/').pop();
  const lines = [];
  lines.push(periode === 'semaine' ? `# Senate report · week of ${keys[keys.length - 1]} to ${keys[0]}` : `# Daily summary · ${keys[0]}`);
  lines.push('');
  lines.push(`- Active time: ${fmtMin(cur.min)} (${delta(cur.min, prev.min) || 'no comparison'})`);
  lines.push(`- Commits: ${cur.commits} ${delta(cur.commits, prev.commits)}`);
  lines.push(`- Green tests: ${cur.testsOk} / ${cur.tests} run`);
  lines.push(`- Gold earned: ${Math.round(cur.or)} · API cost: $${cur.usd.toFixed(1)}`);
  lines.push('');
  lines.push('## By village');
  const vs = Object.entries(cur.villages).sort((a, b) => b[1].min - a[1].min);
  for (const [v, x] of vs) lines.push(`- ${name(v)}: ${fmtMin(x.min)} · ${x.commits} commits · ${Math.round(x.or)} gold`);
  if (!vs.length) lines.push('- no activity');
  const neglected = (S.villages || []).filter((v) => v.idleDays >= 7 && v.xp > 30).sort((a, b) => b.xp - a.xp).slice(0, 5);
  if (neglected.length) {
    lines.push('');
    lines.push('## Neglected villages');
    for (const v of neglected) lines.push(`- ${v.name}: ${Math.floor(v.idleDays)} days without activity${v.objectif && !v.objectif.done ? ` · goal "${v.objectif.texte}" ${v.objectif.have}/${v.objectif.cible}` : ''}`);
  }
  const goals = (S.villages || []).filter((v) => v.objectif);
  if (goals.length) {
    lines.push('');
    lines.push('## Goals');
    for (const v of goals) lines.push(`- ${v.name}: ${v.objectif.texte} · ${v.objectif.have}/${v.objectif.cible} ${RES_NAMES[v.objectif.res] || v.objectif.res}${v.objectif.done ? ' ✔' : ''}`);
  }
  lines.push('');
  lines.push(`Harvest: ${Math.round((1 - (S.food?.saison || 0)) * 100)}% · treasury: ${S.empire?.tresor || 0} gold · title: ${S.empire?.titre || ''}`);
  return lines.join('\n');
}
