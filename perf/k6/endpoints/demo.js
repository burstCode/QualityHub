// Демо-сценарий против учебной мишени (go-httpbin). Нужен, чтобы отладить всю цепочку
//   k6 -> Prometheus -> Grafana -> JSON-итог
// без доступа к стенду ClinicWeb.
//
// Запуск: см. scripts/k6.ps1 или docs/GUIDE.md
import { sleep } from 'k6';
import { buildOptions } from '../lib/config.js';
import { api } from '../lib/http.js';

export { handleSummary } from '../lib/summary.js';

// имя эндпойнта -> пороги
const endpoints = {
  demo_get: { p95Ms: 300 },
  demo_delay: { p95Ms: 600 }, // искусственная задержка 200 мс
  demo_flaky: { p95Ms: 300, maxErrorRate: 0.1 }, // ~5% ответов с кодом 500
};

export const options = buildOptions(endpoints);

export default function () {
  api.get('demo_get', '/get');
  api.get('demo_delay', '/delay/0.2');
  api.get('demo_flaky', '/status/200:95,500:5');
  sleep(0.1 + Math.random() * 0.2);
}
