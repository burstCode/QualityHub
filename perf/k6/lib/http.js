// Обёртка над k6/http: помечает запрос именем эндпойнта и проверяет ответ.
import http from 'k6/http';
import { check } from 'k6';
import { cfg } from './config.js';

// validate(res) -> bool: проверка содержимого ответа (корректность данных, а не только скорость)
export function request(name, method, path, body, params = {}, validate) {
  const url = path.startsWith('http') ? path : `${cfg.baseUrl}${path}`;
  const headers = { ...(params.headers || {}) };
  let payload = null;
  if (body !== undefined && body !== null) {
    payload = typeof body === 'string' ? body : JSON.stringify(body);
    if (!headers['Content-Type']) headers['Content-Type'] = 'application/json';
  }
  const res = http.request(method, url, payload, {
    ...params,
    headers,
    tags: { ...(params.tags || {}), endpoint: name },
  });

  const checks = { [`${name}: статус 2xx`]: (r) => r.status >= 200 && r.status < 300 };
  if (validate) checks[`${name}: ответ корректен`] = validate;
  check(res, checks, { endpoint: name });
  return res;
}

export const api = {
  get: (name, path, params, validate) => request(name, 'GET', path, null, params, validate),
  post: (name, path, body, params, validate) => request(name, 'POST', path, body, params, validate),
};
