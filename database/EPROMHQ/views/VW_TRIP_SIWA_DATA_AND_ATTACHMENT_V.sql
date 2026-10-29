
  CREATE OR REPLACE FORCE EDITIONABLE VIEW "EPROMHQ"."VW_TRIP_SIWA_DATA_AND_ATTACHMENT_V" ("M", "APP_ID", "EMP_NO", "FULL_NAME", "RELATION_DESC", "PROJECT_NAME", "JOB_NAME", "GRADE_NAME", "GRADE_DATE", "BENEFIT_TEXT", "HIRE_DATE", "BIRTH_DATE", "AGE_DAYS_REF", "AGE_MONTHS_REF", "AGE_YEARS_REF", "ROOM_CLASS", "NUM_OF_ROOMS", "LOCATION_ID", "MOBILE_NO", "WHATS_NO", "NOTES", "ATTACH1", "ATTACH2", "ATTACH3", "ATTACH4") AS
  WITH
APP AS (
  SELECT
      a.app_id,
      a.emp_id,                               -- VARCHAR2
      e.emp_name,
      e.project                  AS project_name,
      e.emp_position_name        AS job_name,
      e.current_grade            AS grade_name,
      e.job_date                 AS grade_date,       -- غالبًا VARCHAR2
      NVL(a.emp_last_benefit,'لايوجد استفادات سابقة') AS benefit_text,
      e.hire_date,                                   -- غالبًا VARCHAR2
      e.emp_date_of_birth,                           -- غالبًا VARCHAR2
      a.location_id,
      c.mobile                   AS mobile_no,
      c.mobile                   AS whats_no
  FROM epromhq.trip_applications a
  LEFT JOIN central.xxapex_hr_emp_data e
         ON TO_CHAR(e.emp_number) = a.emp_id          -- مهم: توحيد النوع
  LEFT JOIN central.emp_contact c
         ON TO_CHAR(c.emp_id) = a.emp_id              -- احتياط لو emp_id عندكم NUMBER
  WHERE a.application_status = 'D' and (is_apology is null or is_apology <> 1)
),
ROOMS AS (
  SELECT
      r.app_id,
      LISTAGG(r.room_type, ' / ')
        WITHIN GROUP (ORDER BY r.room_type) AS room_class,
      NVL(SUM(r.num_of_rooms),0) AS num_of_rooms
  FROM epromhq.trip_rooms r
  GROUP BY r.app_id
),
ROWS0 AS (
  /* ===================== سطر العامل ===================== */
  SELECT
      a.app_id                                         AS app_id,
      CAST(a.emp_id AS VARCHAR2(99))                   AS emp_no,       -- ✅ نفس النوع في الفرعين
      CAST(a.emp_name AS VARCHAR2(200))                AS full_name,
      CAST('العامل' AS VARCHAR2(99))                   AS relation_desc,
      CAST(a.project_name AS VARCHAR2(200))            AS project_name,
      CAST(a.job_name AS VARCHAR2(200))                AS job_name,
      CAST(a.grade_name AS VARCHAR2(200))              AS grade_name,

      /* GRADE_DATE -> DATE */
      CASE
        WHEN a.grade_date IS NOT NULL
         AND REGEXP_LIKE(a.grade_date, '^\d{4}-\d{2}-\d{2}$') THEN TO_DATE(a.grade_date,'YYYY-MM-DD')
        WHEN a.grade_date IS NOT NULL
         AND REGEXP_LIKE(a.grade_date, '^\d{2}/\d{2}/\d{4}$') THEN TO_DATE(a.grade_date,'DD/MM/YYYY')
        ELSE NULL
      END                                              AS grade_date,

      CAST(a.benefit_text AS VARCHAR2(4000))           AS benefit_text,

      /* HIRE_DATE -> DATE */
      CASE
        WHEN a.hire_date IS NOT NULL
         AND REGEXP_LIKE(a.hire_date, '^\d{4}-\d{2}-\d{2}$') THEN TO_DATE(a.hire_date,'YYYY-MM-DD')
        WHEN a.hire_date IS NOT NULL
         AND REGEXP_LIKE(a.hire_date, '^\d{2}/\d{2}/\d{4}$') THEN TO_DATE(a.hire_date,'DD/MM/YYYY')
        ELSE NULL
      END                                              AS hire_date,

      /* BIRTH_DATE -> DATE */
      CASE
        WHEN a.emp_date_of_birth IS NOT NULL
         AND REGEXP_LIKE(a.emp_date_of_birth, '^\d{4}-\d{2}-\d{2}$') THEN TO_DATE(a.emp_date_of_birth,'YYYY-MM-DD')
        WHEN a.emp_date_of_birth IS NOT NULL
         AND REGEXP_LIKE(a.emp_date_of_birth, '^\d{2}/\d{2}/\d{4}$') THEN TO_DATE(a.emp_date_of_birth,'DD/MM/YYYY')
        ELSE NULL
      END                                              AS birth_date,

      CAST(r.room_class AS VARCHAR2(4000))             AS room_class,
      CAST(r.num_of_rooms AS NUMBER)                   AS num_of_rooms,
      CAST(a.location_id AS NUMBER)                    AS location_id,
      CAST(a.mobile_no AS VARCHAR2(100))               AS mobile_no,
      CAST(a.whats_no AS VARCHAR2(100))                AS whats_no,
      CAST(NULL AS VARCHAR2(4000))                     AS notes,

      CAST(e.person_id AS NUMBER)                      AS person_id,     -- ✅ للمرفقات HRF_PERSON_ATTACHMENTS
      CAST(1 AS NUMBER)                                AS relation_sort,
      CAST(1 AS NUMBER)                                AS person_seq
  FROM app a
  LEFT JOIN rooms r
    ON r.app_id = a.app_id
  LEFT JOIN central.xxapex_hr_emp_data e
    ON TO_CHAR(e.emp_number) = a.emp_id

  UNION ALL

  /* ===================== سطور المرافقين ===================== */
  SELECT
      a.app_id                                         AS app_id,
      CAST(NULL AS VARCHAR2(99))                       AS emp_no,        -- ✅ نفس النوع
      CAST(c.person_name AS VARCHAR2(200))             AS full_name,
      CAST(c.person_relation AS VARCHAR2(99))          AS relation_desc,
      CAST(a.project_name AS VARCHAR2(200))            AS project_name,
      CAST(NULL AS VARCHAR2(200))                      AS job_name,
      CAST(NULL AS VARCHAR2(200))                      AS grade_name,
      CAST(NULL AS DATE)                               AS grade_date,
      CAST(NULL AS VARCHAR2(4000))                     AS benefit_text,
      CAST(NULL AS DATE)                               AS hire_date,
      CAST(c.person_birthdate AS DATE)                 AS birth_date,
      CAST(NULL AS VARCHAR2(4000))                     AS room_class,
      CAST(NULL AS NUMBER)                             AS num_of_rooms,
      CAST(a.location_id AS NUMBER)                    AS location_id,
      CAST(NULL AS VARCHAR2(100))                      AS mobile_no,
      CAST(NULL AS VARCHAR2(100))                      AS whats_no,
      CAST(NULL AS VARCHAR2(4000))                     AS notes,

      CAST(c.person_id AS NUMBER)                      AS person_id,     -- ✅ موجود عندك
      CAST(
        CASE
          WHEN c.person_relation LIKE 'الزوج%'        THEN 2
          WHEN c.person_relation LIKE 'الابن الأول%'  THEN 3
          WHEN c.person_relation LIKE 'الابن الثانى%' THEN 4
          ELSE 9
        END
      AS NUMBER)                                       AS relation_sort,
      CAST(c.companion_id AS NUMBER)                   AS person_seq
  FROM app a
  JOIN epromhq.trip_companions c
    ON c.app_id = a.app_id
),
AGE_CALC AS (
  SELECT
      r.*,
      TRUNC(SYSDATE) AS ref_date,
      TRUNC(MONTHS_BETWEEN(TRUNC(SYSDATE), r.birth_date) / 12)     AS age_years_ref,
      TRUNC(MOD(MONTHS_BETWEEN(TRUNC(SYSDATE), r.birth_date), 12)) AS age_months_ref,
      TRUNC(
        TRUNC(SYSDATE) -
        ADD_MONTHS(
          r.birth_date,
          TRUNC(MONTHS_BETWEEN(TRUNC(SYSDATE), r.birth_date) / 12) * 12
          + TRUNC(MOD(MONTHS_BETWEEN(TRUNC(SYSDATE), r.birth_date), 12))
        )
      ) AS age_days_ref
  FROM rows0 r
),
NUMS AS (
  SELECT
      a.*,
      DENSE_RANK() OVER (ORDER BY a.app_id) AS app_no
  FROM age_calc a
),
AT_ONE AS (
  SELECT *
  FROM (
    SELECT x.*,
           ROW_NUMBER() OVER (PARTITION BY x.person_id ORDER BY x.attach_id DESC) rn
    FROM epromhq.hrf_person_attachments x
  )
  WHERE rn = 1
)
SELECT
  ROW_NUMBER() OVER (ORDER BY app_no, relation_sort, person_seq) AS m,
  app_id,
  CASE WHEN relation_desc = 'العامل' THEN emp_no END AS emp_no,
  full_name,
  relation_desc,
  project_name,
  job_name,
  grade_name,
  grade_date,
  benefit_text,
  hire_date,
  birth_date,
  age_days_ref,
  age_months_ref,
  age_years_ref,
  room_class,
  num_of_rooms,
  location_id,
  mobile_no,
  whats_no,
  notes,

  NVL2(at.attach1, '<a href="/attach/'||at.attach1||'" data-lightbox="image" data-title="Attachment 1">'
      || CASE WHEN LOWER(APEX_UTIL.GET_SESSION_LANG)='ar-ae' THEN 'عرض' ELSE 'View' END || '</a>', '-') AS attach1,
  NVL2(at.attach2, '<a href="/attach/'||at.attach2||'" data-lightbox="image" data-title="Attachment 2">'
      || CASE WHEN LOWER(APEX_UTIL.GET_SESSION_LANG)='ar-ae' THEN 'عرض' ELSE 'View' END || '</a>', '-') AS attach2,
  NVL2(at.attach3, '<a href="/attach/'||at.attach3||'" data-lightbox="image" data-title="Attachment 3">'
      || CASE WHEN LOWER(APEX_UTIL.GET_SESSION_LANG)='ar-ae' THEN 'عرض' ELSE 'View' END || '</a>', '-') AS attach3,
  NVL2(at.attach4, '<a href="/attach/'||at.attach4||'" data-lightbox="image" data-title="Attachment 4">'
      || CASE WHEN LOWER(APEX_UTIL.GET_SESSION_LANG)='ar-ae' THEN 'عرض' ELSE 'View' END || '</a>', '-') AS attach4

FROM nums n
LEFT JOIN at_one at
  ON at.person_id = n.person_id;
