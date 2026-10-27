-- СИНТЕТИЧЕСКИЕ ДАННЫЕ ДЛЯ ОТЛАДКИ ДАШБОРДОВ.

BEGIN;
SELECT setseed(0.42);

INSERT INTO PROJECT (PROJECT_NAME, PROJECT_DESCRIPTION)
VALUES ('demo-clinic-api', 'Синтетический проект для отладки дашбордов')
ON CONFLICT (PROJECT_NAME) DO NOTHING;

INSERT INTO TEST_CASE (PROJECT_ID, TEST_LEVEL_ID, TEST_CASE_SUITE, TEST_CASE_NAME)
SELECT p.PROJECT_ID, l.TEST_LEVEL_ID,
       'Suite' || (g % 5 + 1),
       'Suite' || (g % 5 + 1) || '.Case' || lpad(g::text, 3, '0')
FROM PROJECT p
JOIN TEST_LEVEL l ON l.TEST_LEVEL_CODE = 'integration'
CROSS JOIN generate_series(1, 40) g
WHERE p.PROJECT_NAME = 'demo-clinic-api'
ON CONFLICT DO NOTHING;

INSERT INTO TEST_RUN (PROJECT_ID, TEST_LEVEL_ID, TEST_RUN_BUILD_NUMBER, TEST_RUN_BRANCH, TEST_RUN_COMMIT_HASH,
                      TEST_RUN_ENVIRONMENT, TEST_RUN_STARTED_AT, TEST_RUN_FINISHED_AT, TEST_RUN_DURATION_MS,
                      TEST_RUN_SOURCE_FORMAT, TEST_RUN_IMPORT_STATUS)
SELECT p.PROJECT_ID, l.TEST_LEVEL_ID, 'demo-' || s.n, 'develop', md5('demo' || s.n), 'ci-stand',
       s.ts, s.ts + make_interval(secs => s.dur_ms / 1000.0), s.dur_ms, 'junit', 3
FROM PROJECT p
JOIN TEST_LEVEL l ON l.TEST_LEVEL_CODE = 'integration'
CROSS JOIN LATERAL (
    SELECT n,
           date_trunc('minute', now()) - ((60 - n) * interval '12 hours') AS ts,
           (180000 + floor(random() * 20000) + CASE WHEN n > 50 THEN 90000 ELSE 0 END)::bigint AS dur_ms
    FROM generate_series(1, 60) n
) s
WHERE p.PROJECT_NAME = 'demo-clinic-api'
ON CONFLICT DO NOTHING;

INSERT INTO TEST_RESULT (TEST_RUN_ID, TEST_CASE_ID, TEST_RESULT_STATUS, TEST_RESULT_DURATION_MS, TEST_RESULT_ERROR_MESSAGE)
SELECT r.TEST_RUN_ID, c.TEST_CASE_ID, x.status, x.dur,
       CASE WHEN x.status = 1 THEN 'Assert.Equal() Failure (синтетические данные)' END
FROM TEST_RUN r
JOIN PROJECT p ON p.PROJECT_ID = r.PROJECT_ID AND p.PROJECT_NAME = 'demo-clinic-api'
JOIN TEST_CASE c ON c.PROJECT_ID = r.PROJECT_ID AND c.TEST_LEVEL_ID = r.TEST_LEVEL_ID
CROSS JOIN LATERAL (SELECT substring(r.TEST_RUN_BUILD_NUMBER FROM 6)::int AS n,
                           right(c.TEST_CASE_NAME, 3)::int AS k) q
CROSS JOIN LATERAL (
    SELECT CASE
             WHEN q.k IN (7, 19, 33) AND random() < 0.25 THEN 1
             WHEN q.n > 50 AND q.k <= 5 AND random() < 0.4 THEN 1
             WHEN random() < 0.01 THEN 1
             ELSE 0
           END AS status,
           (20 + floor(random() * 300) * CASE WHEN q.n > 50 THEN 1.6 ELSE 1 END)::int AS dur
) x
ON CONFLICT DO NOTHING;

INSERT INTO METRIC_VALUE (TEST_RUN_ID, METRIC_ID, METRIC_VALUE_VALUE)
SELECT s.TEST_RUN_ID, m.METRIC_ID,
       CASE m.METRIC_CODE
            WHEN 'pass_rate'    THEN s.pass_rate
            WHEN 'failed_count' THEN s.failed_count
            WHEN 'duration'     THEN s.duration_s
       END
FROM (
    SELECT r.TEST_RUN_ID,
           100.0 * count(*) FILTER (WHERE t.TEST_RESULT_STATUS = 0)
                 / NULLIF(count(*) FILTER (WHERE t.TEST_RESULT_STATUS <> 3), 0) AS pass_rate,
           count(*) FILTER (WHERE t.TEST_RESULT_STATUS IN (1, 2)) AS failed_count,
           r.TEST_RUN_DURATION_MS / 1000.0 AS duration_s
    FROM TEST_RUN r
    JOIN PROJECT p ON p.PROJECT_ID = r.PROJECT_ID AND p.PROJECT_NAME = 'demo-clinic-api'
    JOIN TEST_RESULT t ON t.TEST_RUN_ID = r.TEST_RUN_ID
    GROUP BY r.TEST_RUN_ID, r.TEST_RUN_DURATION_MS
) s
JOIN METRIC_DEFINITION m ON m.METRIC_CODE IN ('pass_rate', 'failed_count', 'duration')
ON CONFLICT DO NOTHING;

COMMIT;
