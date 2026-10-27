// Вход в ClinicWeb: POST /api/Authorization/Login.
// Сессия держится на куках, k6 хранит их в cookie jar
// каждого виртуального пользователя автоматически.

import http from 'k6/http';
import { check, fail } from 'k6';
import { cfg } from '../lib/config.js';

let loggedIn = false; // состояние модуля у каждого VU своё

export function ensureLogin() {
  if (loggedIn) return;

  const login = __ENV.CLINICWEB_LOGIN;
  const password = __ENV.CLINICWEB_PASSWORD;
  if (!login) fail('Не задан CLINICWEB_LOGIN (учётная запись для нагрузочных тестов)');

  const res = http.post(
    `${cfg.baseUrl}/api/Authorization/Login`,
    JSON.stringify({ login, password: password || '', rememberMe: false }),
    { headers: { 'Content-Type': 'application/json' }, tags: { endpoint: 'auth_login' } },
  );

  const ok = check(res, {
    'вход: статус 200': (r) => r.status === 200,
    'вход: без запроса кода доступа': (r) => {
      try { return r.json('needAccessCode') !== true; } catch (e) { return false; }
    },
  }, { endpoint: 'auth_login' });

  if (!ok) fail(`Вход в ClinicWeb не удался: HTTP ${res.status}`);
  loggedIn = true;
}
