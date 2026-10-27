-- 003_seed.sql — справочные данные, без которых система не запустится.

INSERT INTO TEST_LEVEL (TEST_LEVEL_CODE, TEST_LEVEL_NAME, TEST_LEVEL_ORDER) VALUES
    ('unit',        'Модульный',            1),
    ('integration', 'Интеграционный (API)', 2),
    ('e2e',         'Сквозной (UI)',        3),
    ('performance', 'Нагрузочный',          4)
ON CONFLICT (TEST_LEVEL_CODE) DO NOTHING;

INSERT INTO USER_ROLE (USER_ROLE_NAME) VALUES
    ('начальник'), ('тимлид'), ('тестировщик'), ('разработчик')
ON CONFLICT (USER_ROLE_NAME) DO NOTHING;

-- METRIC_SOURCE: 0 результаты тестов, 1 нагрузочный отчёт, 2 мониторинг
-- METRIC_SPRINT_AGGREGATE: 0 среднее, 1 последнее, 2 максимум
INSERT INTO METRIC_DEFINITION
    (METRIC_CODE, METRIC_SOURCE, METRIC_NAME, METRIC_UNIT, METRIC_SPRINT_AGGREGATE, METRIC_DESCRIPTION, METRIC_HIGHER_IS_BETTER) VALUES
    ('pass_rate',     0, 'Доля пройденных тестов',          '%',     0, 'passed / (total - skipped) * 100',                               TRUE),
    ('failed_count',  0, 'Число упавших тестов',            'шт',    2, 'Тесты со статусом "упал" и "ошибка"',                            FALSE),
    ('duration',      0, 'Длительность запуска',            'с',     0, 'finished_at - started_at',                                       FALSE),
    ('flaky_rate',    0, 'Доля нестабильных тестов',        '%',     0, 'Тесты со сменой результата на одном коммите / все тесты',        FALSE),
    ('rps_peak',      1, 'Пиковая пропускная способность',  'req/s', 2, 'Максимум запросов в секунду за запуск',                          TRUE),
    ('response_p95',  1, 'Время ответа p95',                'мс',    0, '95-й перцентиль времени ответа',                                 FALSE),
    ('error_rate',    1, 'Доля ошибок',                     '%',     0, 'Неуспешные запросы / все запросы',                               FALSE),
    ('cpu_peak',      2, 'Пиковая загрузка CPU',            '%',     2, 'Максимум за окно запуска по данным мониторинга',                 FALSE)
ON CONFLICT (METRIC_CODE) DO NOTHING;
