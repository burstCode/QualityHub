-- 002_additions.sql — дополнения к исходной схеме (001_schema.sql оставлена без изменений).
-- Причины и обоснование каждого пункта: docs/schema-review.md.
-- Договорённости по кодам SMALLINT (используются в CHECK и в коде приложения):
--   TEST_RESULT_STATUS      : 0 пройден, 1 упал, 2 ошибка, 3 пропущен
--   TEST_RUN_IMPORT_STATUS  : 0 принят, 1 разобран, 2 ошибка, 3 обработан
--   NOTIFICATION_STATUS     : 0 создано, 1 отправлено, 2 ошибка
--   NOTIFICATION_CHANNEL    : 0 электронная почта, 1 мессенджер MAX
--   THRESHOLD_RULE_SEVERITY : 0 предупреждение, 1 критично
--   METRIC_SOURCE           : 0 результаты тестов, 1 отчёт нагрузочного теста, 2 мониторинг
--   METRIC_SPRINT_AGGREGATE : 0 среднее, 1 последнее, 2 максимум
--   ANALYSIS_FINDING_KIND   : 0 регрессия, 1 нестабильный тест, 2 ухудшение относительно спринта

-- ---------------------------------------------------------------------------
-- 1. Результаты анализа динамики (процесс 4). Без этой таблицы нечем обосновать
--    уведомление о регрессии: NOTIFICATION в исходной схеме ссылалась только на правило порога.
-- ---------------------------------------------------------------------------
CREATE TABLE ANALYSIS_FINDING (
    ANALYSIS_FINDING_ID            BIGSERIAL,
    TEST_RUN_ID                    BIGINT NOT NULL,
    METRIC_ID                      INTEGER,
    TEST_CASE_ID                   BIGINT,
    ANALYSIS_FINDING_KIND          SMALLINT NOT NULL,
    ANALYSIS_FINDING_SEVERITY      SMALLINT NOT NULL,
    ANALYSIS_FINDING_BASELINE      NUMERIC(18,4),
    ANALYSIS_FINDING_OBSERVED      NUMERIC(18,4),
    ANALYSIS_FINDING_SCORE         NUMERIC(18,4),
    ANALYSIS_FINDING_DETAILS       JSONB,
    ANALYSIS_FINDING_CREATED_AT    TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT PK_ANALYSIS_FINDING PRIMARY KEY (ANALYSIS_FINDING_ID),
    CONSTRAINT FK_ANALYSIS_FINDING_TEST_RUN FOREIGN KEY (TEST_RUN_ID) REFERENCES TEST_RUN (TEST_RUN_ID),
    CONSTRAINT FK_ANALYSIS_FINDING_METRIC FOREIGN KEY (METRIC_ID) REFERENCES METRIC_DEFINITION (METRIC_ID),
    CONSTRAINT FK_ANALYSIS_FINDING_TEST_CASE FOREIGN KEY (TEST_CASE_ID) REFERENCES TEST_CASE (TEST_CASE_ID),
    CONSTRAINT CK_ANALYSIS_FINDING_KIND CHECK (ANALYSIS_FINDING_KIND BETWEEN 0 AND 2)
);
COMMENT ON TABLE ANALYSIS_FINDING IS 'Результат анализа динамики: регрессия, нестабильный тест, ухудшение относительно предыдущего спринта.';
COMMENT ON COLUMN ANALYSIS_FINDING.METRIC_ID IS 'Метрика (пусто для находок по отдельному тесту)';
COMMENT ON COLUMN ANALYSIS_FINDING.TEST_CASE_ID IS 'Тест (пусто для находок по метрике запуска)';
COMMENT ON COLUMN ANALYSIS_FINDING.ANALYSIS_FINDING_KIND IS 'Вид: 0 регрессия, 1 нестабильный тест, 2 ухудшение относительно спринта';
COMMENT ON COLUMN ANALYSIS_FINDING.ANALYSIS_FINDING_BASELINE IS 'Значение базовой линии (или предыдущего спринта)';
COMMENT ON COLUMN ANALYSIS_FINDING.ANALYSIS_FINDING_OBSERVED IS 'Наблюдаемое значение';
COMMENT ON COLUMN ANALYSIS_FINDING.ANALYSIS_FINDING_SCORE IS 'Мера отклонения (z-оценка, размер эффекта и т.п.)';
COMMENT ON COLUMN ANALYSIS_FINDING.ANALYSIS_FINDING_DETAILS IS 'Параметры метода и вспомогательные данные в произвольной форме';

-- ---------------------------------------------------------------------------
-- 2. Уведомления: можно создавать и по находке анализа, и по правилу порога;
--    добавлены поля для повторов, ошибок доставки и защиты от дублей (D9).
-- ---------------------------------------------------------------------------
ALTER TABLE NOTIFICATION ALTER COLUMN THRESHOLD_RULE_ID DROP NOT NULL;
ALTER TABLE NOTIFICATION ALTER COLUMN METRIC_VALUE_ID DROP NOT NULL;
ALTER TABLE NOTIFICATION
    ADD COLUMN ANALYSIS_FINDING_ID      BIGINT,
    ADD COLUMN NOTIFICATION_ERROR       TEXT,
    ADD COLUMN NOTIFICATION_ATTEMPTS    SMALLINT NOT NULL DEFAULT 0,
    ADD COLUMN NOTIFICATION_DEDUP_KEY   VARCHAR(200),
    ADD COLUMN NOTIFICATION_EXTERNAL_ID VARCHAR(100);
ALTER TABLE NOTIFICATION
    ADD CONSTRAINT FK_NOTIFICATION_ANALYSIS_FINDING FOREIGN KEY (ANALYSIS_FINDING_ID)
    REFERENCES ANALYSIS_FINDING (ANALYSIS_FINDING_ID);
ALTER TABLE NOTIFICATION
    ADD CONSTRAINT CK_NOTIFICATION_SOURCE CHECK (
        (THRESHOLD_RULE_ID IS NOT NULL AND METRIC_VALUE_ID IS NOT NULL) OR ANALYSIS_FINDING_ID IS NOT NULL);
COMMENT ON COLUMN NOTIFICATION.ANALYSIS_FINDING_ID IS 'Находка анализа, вызвавшая уведомление (вместо правила порога)';
COMMENT ON COLUMN NOTIFICATION.NOTIFICATION_ERROR IS 'Текст последней ошибки доставки';
COMMENT ON COLUMN NOTIFICATION.NOTIFICATION_ATTEMPTS IS 'Число попыток отправки';
COMMENT ON COLUMN NOTIFICATION.NOTIFICATION_DEDUP_KEY IS 'Ключ защиты от повторных уведомлений об одном и том же событии';
COMMENT ON COLUMN NOTIFICATION.NOTIFICATION_EXTERNAL_ID IS 'Идентификатор сообщения во внешнем сервисе (MAX)';

-- ---------------------------------------------------------------------------
-- 3. Адрес пользователя в канале доставки (для MAX это user_id или chat_id бота).
--    Email в APP_USER перестаёт быть обязательным.
-- ---------------------------------------------------------------------------
CREATE TABLE USER_CHANNEL (
    APP_USER_ID                    INTEGER NOT NULL,
    NOTIFICATION_CHANNEL           SMALLINT NOT NULL,
    USER_CHANNEL_ADDRESS           VARCHAR(100) NOT NULL,
    CONSTRAINT PK_USER_CHANNEL PRIMARY KEY (APP_USER_ID, NOTIFICATION_CHANNEL),
    CONSTRAINT FK_USER_CHANNEL_APP_USER FOREIGN KEY (APP_USER_ID) REFERENCES APP_USER (APP_USER_ID)
);
COMMENT ON TABLE USER_CHANNEL IS 'Адрес пользователя в канале доставки (почта, MAX).';
COMMENT ON COLUMN USER_CHANNEL.USER_CHANNEL_ADDRESS IS 'Адрес: e-mail или идентификатор пользователя/чата MAX';
ALTER TABLE APP_USER ALTER COLUMN APP_USER_EMAIL DROP NOT NULL;

-- ---------------------------------------------------------------------------
-- 4. Источники мониторинга: тип источника и запрос (для Prometheus это PromQL,
--    он не помещается в VARCHAR(50) внешнего идентификатора).
-- ---------------------------------------------------------------------------
ALTER TABLE MONITORING_SOURCE
    ADD COLUMN MONITORING_SOURCE_TYPE VARCHAR(30) NOT NULL DEFAULT 'prometheus';
ALTER TABLE MONITORING_SOURCE ALTER COLUMN MONITORING_SOURCE_AUTH_TOKEN DROP NOT NULL;
ALTER TABLE MONITORED_ITEM
    ADD COLUMN MONITORED_ITEM_QUERY TEXT;
ALTER TABLE MONITORED_ITEM ALTER COLUMN MONITORED_ITEM_EXTERNAL_ID DROP NOT NULL;
COMMENT ON COLUMN MONITORING_SOURCE.MONITORING_SOURCE_TYPE IS 'Тип источника: prometheus, elasticsearch, zabbix и др.';
COMMENT ON COLUMN MONITORED_ITEM.MONITORED_ITEM_QUERY IS 'Запрос к источнику (PromQL и т.п.); подстановки {{host}}, {{from}}, {{to}} заполняются при сборе';

-- ---------------------------------------------------------------------------
-- 5. Нагрузочные результаты: добавлены p99 и пропускная способность.
-- ---------------------------------------------------------------------------
ALTER TABLE TEST_RESULT
    ADD COLUMN TEST_RESULT_P99_MS INTEGER,
    ADD COLUMN TEST_RESULT_RPS    NUMERIC(10,2);
COMMENT ON COLUMN TEST_RESULT.TEST_RESULT_P99_MS IS 'Время ответа p99 по запросу, мс (нагрузочный уровень)';
COMMENT ON COLUMN TEST_RESULT.TEST_RESULT_RPS IS 'Пропускная способность по запросу, запросов/с (нагрузочный уровень)';

-- ---------------------------------------------------------------------------
-- 6. Ссылка на запуск в CI (для текста уведомления) и проверки целостности.
-- ---------------------------------------------------------------------------
ALTER TABLE TEST_RUN ADD COLUMN TEST_RUN_CI_URL VARCHAR(500);
COMMENT ON COLUMN TEST_RUN.TEST_RUN_CI_URL IS 'Ссылка на задание или конвейер CI/CD';
COMMENT ON COLUMN TEST_RUN.TEST_RUN_BUILD_NUMBER IS 'Номер сборки в CI/CD; вместе с проектом и уровнем уникален, поэтому для нескольких заданий одного конвейера используйте формат "<конвейер>.<задание>"';

ALTER TABLE TEST_RUN ADD CONSTRAINT CK_TEST_RUN_TIME CHECK (TEST_RUN_FINISHED_AT >= TEST_RUN_STARTED_AT);
ALTER TABLE TEST_RUN ADD CONSTRAINT CK_TEST_RUN_IMPORT_STATUS CHECK (TEST_RUN_IMPORT_STATUS BETWEEN 0 AND 3);
ALTER TABLE TEST_RESULT ADD CONSTRAINT CK_TEST_RESULT_STATUS CHECK (TEST_RESULT_STATUS BETWEEN 0 AND 3);
ALTER TABLE NOTIFICATION ADD CONSTRAINT CK_NOTIFICATION_STATUS CHECK (NOTIFICATION_STATUS BETWEEN 0 AND 2);
ALTER TABLE THRESHOLD_RULE ADD CONSTRAINT CK_THRESHOLD_RULE_SEVERITY CHECK (THRESHOLD_RULE_SEVERITY BETWEEN 0 AND 1);
ALTER TABLE METRIC_DEFINITION ADD CONSTRAINT CK_METRIC_DEFINITION_SOURCE CHECK (METRIC_SOURCE BETWEEN 0 AND 2);
ALTER TABLE METRIC_DEFINITION ADD CONSTRAINT CK_METRIC_DEFINITION_AGGREGATE CHECK (METRIC_SPRINT_AGGREGATE BETWEEN 0 AND 2);
ALTER TABLE SPRINT ADD CONSTRAINT CK_SPRINT_DATES CHECK (SPRINT_END_DATE >= SPRINT_START_DATE);

-- ---------------------------------------------------------------------------
-- 7. Индексы. PostgreSQL не создаёт их автоматически по внешним ключам,
--    а без них при росте данных дашборды и анализ динамики станут медленными.
-- ---------------------------------------------------------------------------
CREATE INDEX IX_TEST_RUN_SERIES        ON TEST_RUN (PROJECT_ID, TEST_LEVEL_ID, TEST_RUN_STARTED_AT DESC);
CREATE INDEX IX_TEST_RUN_STARTED       ON TEST_RUN (TEST_RUN_STARTED_AT);
CREATE INDEX IX_TEST_RESULT_CASE       ON TEST_RESULT (TEST_CASE_ID, TEST_RUN_ID);
CREATE INDEX IX_METRIC_VALUE_METRIC    ON METRIC_VALUE (METRIC_ID, TEST_RUN_ID);
CREATE INDEX IX_THRESHOLD_RULE_PROJECT ON THRESHOLD_RULE (PROJECT_ID, METRIC_ID) WHERE THRESHOLD_RULE_IS_ACTIVE;
CREATE INDEX IX_NOTIFICATION_USER      ON NOTIFICATION (APP_USER_ID, NOTIFICATION_DEDUP_KEY, NOTIFICATION_CREATED_AT DESC);
CREATE INDEX IX_NOTIFICATION_STATUS    ON NOTIFICATION (NOTIFICATION_STATUS) WHERE NOTIFICATION_STATUS <> 1;
CREATE INDEX IX_NOTIFICATION_RULE      ON NOTIFICATION (THRESHOLD_RULE_ID);
CREATE INDEX IX_NOTIFICATION_VALUE     ON NOTIFICATION (METRIC_VALUE_ID);
CREATE INDEX IX_NOTIFICATION_FINDING   ON NOTIFICATION (ANALYSIS_FINDING_ID);
CREATE INDEX IX_ANALYSIS_FINDING_RUN   ON ANALYSIS_FINDING (TEST_RUN_ID);
CREATE INDEX IX_ANALYSIS_FINDING_CASE  ON ANALYSIS_FINDING (TEST_CASE_ID) WHERE TEST_CASE_ID IS NOT NULL;
CREATE INDEX IX_INFRA_SAMPLE_RUN_ITEM  ON INFRA_SAMPLE (TEST_RUN_ID, MONITORED_ITEM_ID, INFRA_SAMPLE_TIME);
CREATE INDEX IX_INFRA_SAMPLE_ITEM      ON INFRA_SAMPLE (MONITORED_ITEM_ID);
CREATE INDEX IX_MONITORED_ITEM_SOURCE  ON MONITORED_ITEM (MONITORING_SOURCE_ID);
CREATE INDEX IX_API_TOKEN_PROJECT      ON API_TOKEN (PROJECT_ID) WHERE API_TOKEN_IS_ACTIVE;
CREATE INDEX IX_SPRINT_PROJECT_DATES   ON SPRINT (PROJECT_ID, SPRINT_START_DATE, SPRINT_END_DATE);
CREATE INDEX IX_SUBSCRIPTION_PROJECT   ON SUBSCRIPTION (PROJECT_ID);
CREATE INDEX IX_PROJECT_ACCESS_PROJECT ON PROJECT_ACCESS (PROJECT_ID);
CREATE INDEX IX_REPORT_PROJECT         ON REPORT (PROJECT_ID, REPORT_CREATED_AT DESC);

-- ---------------------------------------------------------------------------
-- 8. Представления для Grafana и отчётов (дашборды остаются простыми, а логика
--    расчёта pass rate лежит в одном месте).
-- ---------------------------------------------------------------------------
CREATE VIEW V_RUN_SUMMARY AS
SELECT r.TEST_RUN_ID,
       p.PROJECT_NAME,
       l.TEST_LEVEL_CODE,
       r.TEST_RUN_BUILD_NUMBER,
       r.TEST_RUN_BRANCH,
       r.TEST_RUN_ENVIRONMENT,
       r.TEST_RUN_STARTED_AT,
       r.TEST_RUN_DURATION_MS,
       COUNT(t.TEST_RESULT_ID)                                              AS TOTAL_COUNT,
       COUNT(*) FILTER (WHERE t.TEST_RESULT_STATUS = 0)                     AS PASSED_COUNT,
       COUNT(*) FILTER (WHERE t.TEST_RESULT_STATUS IN (1, 2))               AS FAILED_COUNT,
       COUNT(*) FILTER (WHERE t.TEST_RESULT_STATUS = 3)                     AS SKIPPED_COUNT,
       ROUND(100.0 * COUNT(*) FILTER (WHERE t.TEST_RESULT_STATUS = 0)
             / NULLIF(COUNT(*) FILTER (WHERE t.TEST_RESULT_STATUS <> 3), 0), 2) AS PASS_RATE
FROM TEST_RUN r
JOIN PROJECT p ON p.PROJECT_ID = r.PROJECT_ID
JOIN TEST_LEVEL l ON l.TEST_LEVEL_ID = r.TEST_LEVEL_ID
LEFT JOIN TEST_RESULT t ON t.TEST_RUN_ID = r.TEST_RUN_ID
GROUP BY r.TEST_RUN_ID, p.PROJECT_NAME, l.TEST_LEVEL_CODE;
COMMENT ON VIEW V_RUN_SUMMARY IS 'Сводка по запускам: число тестов по статусам и pass rate.';

CREATE VIEW V_METRIC_SERIES AS
SELECT p.PROJECT_NAME,
       l.TEST_LEVEL_CODE,
       m.METRIC_CODE,
       m.METRIC_NAME,
       m.METRIC_UNIT,
       r.TEST_RUN_ID,
       r.TEST_RUN_BUILD_NUMBER,
       r.TEST_RUN_STARTED_AT,
       v.METRIC_VALUE_VALUE
FROM METRIC_VALUE v
JOIN METRIC_DEFINITION m ON m.METRIC_ID = v.METRIC_ID
JOIN TEST_RUN r ON r.TEST_RUN_ID = v.TEST_RUN_ID
JOIN PROJECT p ON p.PROJECT_ID = r.PROJECT_ID
JOIN TEST_LEVEL l ON l.TEST_LEVEL_ID = r.TEST_LEVEL_ID;
COMMENT ON VIEW V_METRIC_SERIES IS 'Временные ряды метрик по запускам (источник для графиков Grafana).';
