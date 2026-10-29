
  CREATE OR REPLACE FORCE EDITIONABLE VIEW "EPROMHQ"."VAC_HISTORY_VIEW" ("EMP_ID", "SUMMER_2022", "SUMMER_2023", "SUMMER_2024", "SUMMER_2025", "WINTER_2022", "WINTER_2023", "WINTER_2024", "WINTER_2025", "WINTER_2026", "ALL_BENEFITS") AS
  SELECT
    x.emp_id,

    MAX(CASE WHEN REGEXP_LIKE(x.history, 'مصيف 2022') THEN 'Y' END) AS SUMMER_2022,
    MAX(CASE WHEN REGEXP_LIKE(x.history, 'مصيف 2023') THEN 'Y' END) AS SUMMER_2023,
    MAX(CASE WHEN REGEXP_LIKE(x.history, 'مصيف 2024') THEN 'Y' END) AS SUMMER_2024,
    MAX(CASE WHEN x.summer_2025 = 'Y' THEN 'Y' END) AS SUMMER_2025,

    MAX(CASE WHEN REGEXP_LIKE(x.history, 'مشتى 2022|مشتي 2022') THEN 'Y' END) AS WINTER_2022,
    MAX(CASE WHEN REGEXP_LIKE(x.history, 'مشتى 2023|مشتي 2023') THEN 'Y' END) AS WINTER_2023,
    MAX(CASE WHEN REGEXP_LIKE(x.history, 'مشتى 2024|مشتي 2024') THEN 'Y' END) AS WINTER_2024,
    MAX(CASE WHEN REGEXP_LIKE(x.history, 'مشتى 2025|مشتي 2025') THEN 'Y' END) AS WINTER_2025,
    MAX(CASE WHEN REGEXP_LIKE(x.history, 'مشتى 2026|مشتي 2026') THEN 'Y' END) AS WINTER_2026,

    RTRIM(
          MAX(CASE WHEN REGEXP_LIKE(x.history, 'مصيف 2022') THEN 'مصيف 2022 ' END)
       || MAX(CASE WHEN REGEXP_LIKE(x.history, 'مشتى 2022|مشتي 2022') THEN 'مشتى 2022 ' END)
       || MAX(CASE WHEN REGEXP_LIKE(x.history, 'مصيف 2023') THEN 'مصيف 2023 ' END)
       || MAX(CASE WHEN REGEXP_LIKE(x.history, 'مشتى 2023|مشتي 2023') THEN 'مشتى 2023 ' END)
       || MAX(CASE WHEN REGEXP_LIKE(x.history, 'مصيف 2024') THEN 'مصيف 2024 ' END)
       || MAX(CASE WHEN REGEXP_LIKE(x.history, 'مشتى 2024|مشتي 2024') THEN 'مشتى 2024 ' END)
       || MAX(CASE WHEN x.summer_2025 = 'Y' THEN 'مصيف 2025 ' END)
       || MAX(CASE WHEN REGEXP_LIKE(x.history, 'مشتى 2025|مشتي 2025') THEN 'مشتى 2025 ' END)
       || MAX(CASE WHEN REGEXP_LIKE(x.history, 'مشتى 2026|مشتي 2026') THEN 'مشتى 2026 ' END)
    ) AS ALL_BENEFITS

FROM
(
    SELECT
        vh.emp_id,
        vh.history,
        CASE
            WHEN va.emp_id IS NOT NULL THEN 'Y'
        END AS summer_2025
    FROM EPROMHQ.VAC_HISTORY vh
    LEFT JOIN
    (
        SELECT DISTINCT emp_id
        FROM EPROMHQ.VAC_UNIT_ALLOCATION
        WHERE trip_id = 4
          AND status_id = 1
    ) va
        ON va.emp_id = vh.emp_id
) x
GROUP BY x.emp_id;
