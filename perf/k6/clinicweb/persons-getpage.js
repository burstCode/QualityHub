// Нагрузка на один метод: POST /api/Persons/GetPage (список пациентов).
// Это ШАБЛОН для остальных методов ClinicWeb: скопируйте файл, смените имя эндпойнта, путь и тело.
//
// Форма запроса взята из исходников бэкенда: GetPageRequest<Person.Metadata>
//   { orderParameters: [], paginationOptions: { startIndex, length }, filters: { flags: { simpleFields: true } } }
// ПРОВЕРИТЬ НА СТЕНДЕ: имена полей ответа (ожидается список в свойстве "list") и порог p95 —
// 800 мс взят как отправная точка, подберите по результатам smoke-прогона.
import { sleep } from 'k6';
import { buildOptions } from '../lib/config.js';
import { api } from '../lib/http.js';
import { ensureLogin } from './auth.js';

export { handleSummary } from '../lib/summary.js';

const endpoints = {
  persons_getpage: { p95Ms: 800 },
};

export const options = buildOptions(endpoints);

// Размер страницы: 10 строк — лёгкий запрос, 200 и больше — тяжёлый (сотни килобайт в ответе)
const pageSize = Number(__ENV.K6_PAGE_SIZE) || 10;

export default function () {
  ensureLogin();

  api.post(
    'persons_getpage',
    '/api/Persons/GetPage',
    {
      orderParameters: [],
      paginationOptions: { startIndex: 0, length: pageSize },
      filters: { flags: { simpleFields: true } },
    },
    {},
    // Проверяем не только статус, но и что пришёл разбираемый JSON.
    // Для больших страниц разбор JSON грузил бы сам k6, поэтому проверяем начало ответа.
    (r) => {
      if (pageSize > 50) return typeof r.body === 'string' && r.body.startsWith('{"list":[');
      try { return r.json() !== null; } catch (e) { return false; }
    },
  );

  sleep(0.2 + Math.random() * 0.5);
}
