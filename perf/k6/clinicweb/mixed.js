// Смешанная нагрузка на ClinicWeb: каждая итерация вызывает случайный метод из пула endpoints.json
// (страницы списков GetPage и справочные GET-методы без параметров). Это только чтение, данные не меняются.
//
// Пул построен сканированием контроллеров и пробным вызовом каждого метода под тестовой учётной записью:
// в него вошли только методы, ответившие 200. Методы с ответом больше 1 МБ исключены, чтобы упираться
// в сервер, а не в сеть генератора.
//
//   .\scripts\k6.ps1 -Script clinicweb/mixed.js -Mode stress -Rate 25 -BaseUrl http://host:port -Env dev
import { sleep } from 'k6';
import { Counter } from 'k6/metrics';
import { buildOptions } from '../lib/config.js';
import { api } from '../lib/http.js';
import { ensureLogin } from './auth.js';

export { handleSummary } from '../lib/summary.js';

const pool = JSON.parse(open('./endpoints.json'));

// Отдельные метки для страниц и справочников: по каждому из ~340 методов пороги не заводим
const endpoints = {
  mixed_page: { p95Ms: 3000, maxErrorRate: 0.05 },
  mixed_get: { p95Ms: 2000, maxErrorRate: 0.05 },
};

export const options = buildOptions(endpoints);

// Ошибки с разбивкой по методу: заполняется только при сбоях, поэтому число серий невелико
const failures = new Counter('mixed_failures');

const pageBody = {
  orderParameters: [],
  paginationOptions: { startIndex: 0, length: 10 },
  filters: { flags: { simpleFields: true } },
};

export default function () {
  ensureLogin();

  const ep = pool[Math.floor(Math.random() * pool.length)];
  const name = ep.kind === 'page' ? 'mixed_page' : 'mixed_get';
  const validate = (r) => typeof r.body === 'string' && r.body.length > 2;

  const res = ep.method === 'POST'
    ? api.post(name, ep.path, pageBody, {}, validate)
    : api.get(name, ep.path, {}, validate);

  if (res.status < 200 || res.status >= 300) failures.add(1, { path: ep.path, code: String(res.status) });

  sleep(0.1 + Math.random() * 0.4);
}
