// handleSummary: сохраняет итог прогона в двух файлах и печатает краткую сводку в консоль.
//   /results/k6-<build>.json      компактный нормализованный итог (формат qualityhub.k6/1) —
//                                  именно его будет принимать парсер QualityHub
//   /results/k6-<build>.raw.json  полный итог k6 как есть (для отладки парсера)
import { cfg } from './config.js';

const round = (x, digits = 3) =>
  x === undefined || x === null || Number.isNaN(x) ? null : Number(Number(x).toFixed(digits));

export function handleSummary(data) {
  const metrics = data.metrics || {};
  const val = (name, key) => (metrics[name] && metrics[name].values ? metrics[name].values[key] : undefined);

  const durationMs = data.state && data.state.testRunDurationMs ? data.state.testRunDurationMs : 0;
  const finishedAt = new Date();
  const startedAt = new Date(finishedAt.getTime() - durationMs);

  const endpoints = [];
  for (const key of Object.keys(metrics)) {
    const m = /^http_req_duration\{endpoint:(.+)\}$/.exec(key);
    if (!m) continue;
    const name = m[1];
    endpoints.push({
      name,
      requests: round(val(`http_reqs{endpoint:${name}}`, 'count'), 0),
      rps: round(val(`http_reqs{endpoint:${name}}`, 'rate')),
      errorRate: round(val(`http_req_failed{endpoint:${name}}`, 'rate'), 4),
      avgMs: round(val(key, 'avg')),
      p95Ms: round(val(key, 'p(95)')),
      p99Ms: round(val(key, 'p(99)')),
      maxMs: round(val(key, 'max')),
    });
  }

  const thresholds = [];
  for (const [metricName, metric] of Object.entries(metrics)) {
    if (!metric.thresholds) continue;
    for (const [expr, res] of Object.entries(metric.thresholds)) {
      thresholds.push({ metric: metricName, expression: expr, ok: res.ok !== undefined ? res.ok : !res.failed });
    }
  }

  const result = {
    schema: 'qualityhub.k6/1',
    project: cfg.project,
    level: 'performance',
    environment: cfg.env,
    version: cfg.version,
    commit: cfg.commit,
    build: cfg.build,
    mode: cfg.mode,
    baseUrl: cfg.baseUrl,
    startedAt: startedAt.toISOString(),
    finishedAt: finishedAt.toISOString(),
    durationMs,
    maxVus: round(val('vus_max', 'max'), 0),
    totals: {
      requests: round(val('http_reqs', 'count'), 0),
      rps: round(val('http_reqs', 'rate')),
      errorRate: round(val('http_req_failed', 'rate'), 4),
      avgMs: round(val('http_req_duration', 'avg')),
      p95Ms: round(val('http_req_duration', 'p(95)')),
      p99Ms: round(val('http_req_duration', 'p(99)')),
      checksRate: round(val('checks', 'rate'), 4),
    },
    thresholds,
    endpoints,
  };

  const lines = [];
  lines.push('');
  lines.push(`QualityHub: прогон ${cfg.build} (${cfg.mode}), проект ${cfg.project}, стенд ${cfg.env}`);
  lines.push(`  запросов: ${result.totals.requests}, RPS: ${result.totals.rps}, ошибок: ${result.totals.errorRate}`);
  lines.push(`  время ответа, мс: avg ${result.totals.avgMs}, p95 ${result.totals.p95Ms}, p99 ${result.totals.p99Ms}`);
  for (const e of endpoints) {
    lines.push(`  - ${e.name}: n=${e.requests}, p95=${e.p95Ms} мс, ошибок=${e.errorRate}`);
  }
  const failed = thresholds.filter((t) => !t.ok);
  lines.push(failed.length === 0 ? '  пороги: все выполнены' : `  пороги НЕ выполнены: ${failed.length}`);
  for (const t of failed) lines.push(`    x ${t.metric} ${t.expression}`);
  // В контейнере результаты пишутся в /results (том из compose); на раннере без Docker задайте RESULTS_DIR
  const dir = (__ENV.RESULTS_DIR || '/results').replace(/[\\/]+$/, '');
  lines.push(`  результат: ${dir}/k6-${cfg.build}.json`);
  lines.push('');

  return {
    stdout: lines.join('\n'),
    [`${dir}/k6-${cfg.build}.json`]: JSON.stringify(result, null, 2),
    [`${dir}/k6-${cfg.build}.raw.json`]: JSON.stringify(data, null, 2),
  };
}
