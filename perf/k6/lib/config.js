// Общая конфигурация k6-сценариев QualityHub.
// Всё настраивается переменными окружения (см. deploy/compose.yaml, сервис k6).

const num = (value, fallback) => {
  if (value === undefined || value === '') return fallback;
  const n = Number(value);
  return Number.isFinite(n) ? n : fallback;
};

export const cfg = {
  baseUrl: (__ENV.BASE_URL || 'http://localhost:8080').replace(/\/+$/, ''),
  project: __ENV.QH_PROJECT || 'demo',
  env: __ENV.QH_ENV || 'local',
  version: __ENV.QH_VERSION || 'dev',
  commit: __ENV.QH_COMMIT || '',
  build: __ENV.QH_BUILD || 'adhoc',
  mode: (__ENV.K6_MODE || 'smoke').toLowerCase(),
  timeScale: num(__ENV.K6_TIME_SCALE, 1),
  rate: num(__ENV.K6_RATE, 20),
  soakSeconds: num(__ENV.K6_SOAK_SECONDS, 1800),
  insecureTls: __ENV.K6_INSECURE === '1',
};

const secs = (s) => `${Math.max(1, Math.round(s * cfg.timeScale))}s`;

function arrival(stages, maxVusFactor = 10) {
  return {
    executor: 'ramping-arrival-rate',
    startRate: 1,
    timeUnit: '1s',
    preAllocatedVUs: Math.max(5, Math.ceil(cfg.rate)),
    maxVUs: Math.max(20, Math.ceil(cfg.rate * maxVusFactor)),
    stages,
  };
}

export function scenarios() {
  const r = cfg.rate;
  switch (cfg.mode) {
    case 'smoke': // проверка, что сценарий вообще работает
      return { smoke: { executor: 'constant-vus', vus: 1, duration: secs(20) } };
    case 'load': // ожидаемая рабочая нагрузка
      return {
        load: arrival([
          { target: r, duration: secs(60) },
          { target: r, duration: secs(180) },
          { target: 0, duration: secs(30) },
        ]),
      };
    case 'stress': // ступени до отказа: ищем "колено"
      return {
        stress: arrival(
          [0.5, 1, 2, 4, 8].map((m) => ({ target: Math.round(r * m), duration: secs(60) })),
          20,
        ),
      };
    case 'spike': // резкий всплеск
      return {
        spike: arrival([
          { target: r, duration: secs(60) },
          { target: r * 5, duration: secs(10) },
          { target: r * 5, duration: secs(60) },
          { target: r, duration: secs(10) },
          { target: r, duration: secs(60) },
        ], 20),
      };
    case 'soak': // длительная постоянная нагрузка (утечки памяти и сессий)
      return {
        soak: {
          executor: 'constant-arrival-rate',
          rate: r,
          timeUnit: '1s',
          duration: secs(cfg.soakSeconds),
          preAllocatedVUs: Math.max(5, Math.ceil(r)),
          maxVUs: Math.max(20, Math.ceil(r * 10)),
        },
      };
    default:
      throw new Error(`Неизвестный режим K6_MODE="${cfg.mode}". Допустимо: smoke, load, stress, spike, soak`);
  }
}

// endpoints: { имя: { p95Ms, maxErrorRate? } }
// Для каждого эндпойнта создаются пороги. Это нужно дважды: проверка качества и то, что k6
// вообще считает по эндпойнту отдельную статистику.
export function buildOptions(endpoints) {
  const thresholds = {
    http_req_failed: ['rate<0.05'],
    checks: ['rate>0.95'],
  };
  for (const [name, spec] of Object.entries(endpoints)) {
    thresholds[`http_req_duration{endpoint:${name}}`] = [`p(95)<${spec.p95Ms}`];
    thresholds[`http_req_failed{endpoint:${name}}`] = [`rate<=${spec.maxErrorRate ?? 0.01}`];
    thresholds[`http_reqs{endpoint:${name}}`] = ['count>=0'];
  }
  return {
    scenarios: scenarios(),
    thresholds,
    tags: { project: cfg.project, env: cfg.env, version: cfg.version, testid: cfg.build },
    summaryTrendStats: ['avg', 'min', 'med', 'p(90)', 'p(95)', 'p(99)', 'max'],
    insecureSkipTLSVerify: cfg.insecureTls,
    noCookiesReset: true,
    systemTags: ['status', 'method', 'group', 'check', 'error', 'error_code', 'scenario', 'expected_response'],
  };
}
