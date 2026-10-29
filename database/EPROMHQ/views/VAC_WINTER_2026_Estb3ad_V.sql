
  CREATE OR REPLACE FORCE EDITIONABLE VIEW "EPROMHQ"."VAC_WINTER_2026_Estb3ad_V" ("M", "WINTER_APP_ID", "EMP_NO", "FULL_NAME", "RELATION_DESC", "PROJECT_NAME", "JOB_NAME", "GRADE_NAME", "GRADE_DATE", "BENEFIT_TEXT", "HIRE_DATE", "BIRTH_DATE", "AGE_DAYS_25_1_2025", "AGE_MONTHS_25_1_2025", "AGE_YEARS_25_1_2025", "ROOM_CLASS", "NUM_OF_ROOMS", "LOCATION_ID", "TRANSPORTATION_TYPE", "MOBILE_NO", "WHATS_NO", "NOTES", "IS_APOLOGY") AS
  WITH APP AS (
    -- بيانات الطلبات المقبولة لمشتى 2026
    SELECT
        V.WINTER_APP_ID,
        V.EMP_ID,
        V.EMP_NAME,
        V.PROJECT,
        V.EMP_POSITION_NAME,
        V.GRADE_NAME,
        V.JOB_DATE,                -- نستخدمه كتاريخ الحصول على المستوى
        V.ALL_BENEFITS,
        V.HIRE_DATE,
        V.EMP_DATE_OF_BIRTH,       -- نص، هنحوّله لتاريخ في FAMILY_ROWS
        V.TRIP_ID,
        V.MOBILE,
        NULL AS WHATS,
        T.TRIP_YEAR,
        T.TRIP_TYPE,
        B.PREV_TEXT            AS NOTES,
        WA.LOCATION_ID         AS LOCATION_ID,
        WA.TRANSPORTATION_TYPE AS TRANSPORTATION_TYPE,
        wa.IS_APOLOGY
    FROM VAC_WINTER_APP_VIEW V
         JOIN VAC_TRIPS T
           ON T.TRIP_ID = V.TRIP_ID
         LEFT JOIN central.EMP_CONTACT P
           ON P.EMP_ID = V.EMP_ID
         LEFT JOIN VAC_PREV_BENEFITS_TEXT B
           ON B.EMP_ID = V.EMP_ID
         LEFT JOIN VAC_WINTER_APPLICATIONS WA
           ON WA.WINTER_APP_ID = V.WINTER_APP_ID
    WHERE V.APPLICATION_STATUS = 'N'
      AND T.TRIP_YEAR = 2026
),
ROOMS AS (
    -- تجميع نوع الغرفة وعدد الغرف لكل طلب
    SELECT
        WINTER_APP_ID,
        LISTAGG(ROOM_TYPE, ' / ')
            WITHIN GROUP (ORDER BY ROOM_TYPE) AS ROOM_TYPE,
        SUM(NUM_OF_ROOMS) AS NUM_OF_ROOMS
    FROM EPROMHQ.VAC_WINTER_ROOMS
    GROUP BY WINTER_APP_ID
),
FAMILY_ROWS AS (
    ------------------------------------------------------------------
    -- سطر العامل
    ------------------------------------------------------------------
    SELECT
        A.WINTER_APP_ID,
        A.EMP_ID,
        A.EMP_NAME              AS PERSON_NAME,
        'العامل'               AS RELATION_NAME,
        CASE
            WHEN A.EMP_DATE_OF_BIRTH IS NOT NULL
             AND REGEXP_LIKE(A.EMP_DATE_OF_BIRTH, '^\d{4}-\d{2}-\d{2}$') THEN
                TO_DATE(A.EMP_DATE_OF_BIRTH, 'YYYY-MM-DD')
            WHEN A.EMP_DATE_OF_BIRTH IS NOT NULL
             AND REGEXP_LIKE(A.EMP_DATE_OF_BIRTH, '^\d{2}/\d{2}/\d{4}$') THEN
                TO_DATE(A.EMP_DATE_OF_BIRTH, 'DD/MM/YYYY')
            ELSE
                null
        END                      AS BIRTH_DATE,
        A.PROJECT,
        A.EMP_POSITION_NAME,
        A.GRADE_NAME,
        A.JOB_DATE,
        A.ALL_BENEFITS,
        A.HIRE_DATE,
        R.ROOM_TYPE,
        R.NUM_OF_ROOMS,
        A.MOBILE,
        A.MOBILE  AS WHATS,
        A.NOTES,
        A.LOCATION_ID,
        A.TRANSPORTATION_TYPE,
        1                       AS RELATION_SORT,
        1                       AS PERSON_SEQ,
        a.IS_APOLOGY
    FROM APP A
    LEFT JOIN ROOMS R
      ON R.WINTER_APP_ID = A.WINTER_APP_ID

    UNION ALL

    ------------------------------------------------------------------
    -- سطور الزوج/الزوجة والأبناء
    ------------------------------------------------------------------
    SELECT
        A.WINTER_APP_ID,
        NULL                     AS EMP_ID,
        C.PERSON_NAME            AS PERSON_NAME,
        C.PERSON_RELATION        AS RELATION_NAME,
        NVL(C.PERSON_BIRTHDATE, k.DATE_OF_BIRTH) AS BIRTH_DATE,   -- DATE بالفعل
        A.PROJECT,
        NULL AS EMP_POSITION_NAME,
        NULL AS GRADE_NAME,
        NULL AS JOB_DATE,
        NULL AS ALL_BENEFITS,
        NULL AS HIRE_DATE,
        NULL AS ROOM_TYPE,
        NULL AS NUM_OF_ROOMS,
        NULL AS MOBILE,
        NULL AS WHATS,
        A.NOTES,
        A.LOCATION_ID,
        A.TRANSPORTATION_TYPE,
        CASE
            WHEN C.PERSON_RELATION LIKE 'الزوج%'         THEN 2
            WHEN C.PERSON_RELATION LIKE 'الابن الأول%'   THEN 3
            WHEN C.PERSON_RELATION LIKE 'الابن الثانى%'  THEN 4
            ELSE 9
        END                      AS RELATION_SORT,
        C.COMPANION_ID           AS PERSON_SEQ,
        a.IS_APOLOGY  -- المرافقين لهم نفس اعتذار العامل
    FROM APP A
         JOIN EPROMHQ.VAC_WINTER_COMPANIONS C
           ON C.WINTER_APP_ID = A.WINTER_APP_ID
         LEFT JOIN central.XXAPEX_HR_EMP_RELATIVES k
           ON k.RELATIVE_PERSON_ID = C.PERSON_ID
         LEFT JOIN ROOMS R
           ON R.WINTER_APP_ID = A.WINTER_APP_ID
),
AGE_CALC AS (
    -- حساب السن باليوم/الشهر/السنة في 25-01-2025
    SELECT
        F.*,
        DATE '2026-01-25' AS REF_DATE,
        TRUNC(MONTHS_BETWEEN(DATE '2026-01-25', F.BIRTH_DATE) / 12)        AS AGE_YEARS,
        TRUNC(MOD(MONTHS_BETWEEN(DATE '2026-01-25', F.BIRTH_DATE), 12))     AS AGE_MONTHS,
        TRUNC(
            DATE '2026-01-25'
            - ADD_MONTHS(
                  F.BIRTH_DATE,
                  TRUNC(MONTHS_BETWEEN(DATE '2026-01-25', F.BIRTH_DATE) / 12) * 12
                  + TRUNC(MOD(MONTHS_BETWEEN(DATE '2026-01-25', F.BIRTH_DATE), 12))
              )
        ) AS AGE_DAYS
    FROM FAMILY_ROWS F
),
WITH_FAMILY_NO AS (
    -- رقم لكل أسرة علشان نرقّم السطور بالترتيب
    SELECT
        A.*,
        DENSE_RANK() OVER (ORDER BY A.WINTER_APP_ID) AS FAMILY_NO
    FROM AGE_CALC A
)
SELECT
    ------------------------------------------------------------------
    -- م = رقم السطر العام
    ------------------------------------------------------------------
    ROW_NUMBER() OVER (
        ORDER BY FAMILY_NO, RELATION_SORT, PERSON_SEQ
    )                           AS M,
WINTER_APP_ID,
    ------------------------------------------------------------------
    -- رقم وظيفي (يظهر في سطر العامل بس)
    ------------------------------------------------------------------
    CASE
        WHEN RELATION_NAME = 'العامل' THEN EMP_ID
    END                         AS EMP_NO,

    ------------------------------------------------------------------
    -- باقي الأعمدة
    ------------------------------------------------------------------
    PERSON_NAME                 AS FULL_NAME,         -- الإسم
    RELATION_NAME               AS RELATION_DESC,     -- صلة القرابة
    PROJECT                     AS PROJECT_NAME,      -- المشروع
    EMP_POSITION_NAME           AS JOB_NAME,          -- الوظيفة
    GRADE_NAME                  AS GRADE_NAME,        -- المستوى الوظيفي
    JOB_DATE                    AS GRADE_DATE,        -- تاريخ الحصول على المستوى
    ALL_BENEFITS                AS BENEFIT_TEXT,      -- الإستفادة
    HIRE_DATE                   AS HIRE_DATE,         -- تاريخ التعيين
    BIRTH_DATE                  AS BIRTH_DATE,        -- تاريخ الميلاد
    AGE_DAYS                    AS AGE_DAYS_25_1_2025,
    AGE_MONTHS                  AS AGE_MONTHS_25_1_2025,
    AGE_YEARS                   AS AGE_YEARS_25_1_2025,
    ROOM_TYPE                   AS ROOM_CLASS,        -- تصنيف الغرف
    NUM_OF_ROOMS                AS NUM_OF_ROOMS,      -- عدد الغرف
    LOCATION_ID                 AS LOCATION_ID,       -- من VAC_WINTER_APPLICATIONS
    TRANSPORTATION_TYPE         AS TRANSPORTATION_TYPE, -- وسيلة الانتقال
    MOBILE                      AS MOBILE_NO,         -- رقم الموبايل
    WHATS                       AS WHATS_NO,          -- رقم الواتس آب
    NOTES                       AS NOTES,
    ------------------------------------------------------------------
    -- حقل الاعتذار (للعامل والمرافقين)
    ------------------------------------------------------------------
    CASE
        WHEN IS_APOLOGY = 'true' THEN 'معتذر'
        WHEN IS_APOLOGY IS NULL THEN 'غير معتذر'
        ELSE IS_APOLOGY
    END  AS IS_APOLOGY
FROM WITH_FAMILY_NO;
