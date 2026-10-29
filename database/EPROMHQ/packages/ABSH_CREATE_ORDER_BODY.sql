
  CREATE OR REPLACE EDITIONABLE PACKAGE BODY "EPROMHQ"."ABSH_CREATE_ORDER" AS

   FUNCTION ASSIGN_STAFF
   (
      P_INDV_RFQ_ID     IN NUMBER
     ,P_ONE_SCHED_ID    IN NUMBER
     ,P_SERVICE_AREA_ID IN NUMBER DEFAULT NULL
     ,P_USED_STAFF_IDS  IN VARCHAR2 DEFAULT NULL
   ) RETURN VARCHAR2 IS
      V_RESULT_RAW CLOB;
      V_STEP       VARCHAR2(200);
      V_STAFF_ID   NUMBER;
      V_STAFF_ROLE VARCHAR2(100);
      V_RESULT     VARCHAR2(200);
   BEGIN
      V_STEP := 'START';

      ABSH_UTIL_PKG.LOG_ERROR(
         P_ERROR_MESSAGE => '[STEP] Starting Assign_staff | RFQ_ID: ' || P_INDV_RFQ_ID || ' | Schedule_ID: ' || P_ONE_SCHED_ID || ' | Service_Area_ID: ' || P_SERVICE_AREA_ID || ' | Used_Staff: ' || P_USED_STAFF_IDS,
         P_CALLING_PROC  => 'ABSH_CREATE_ORDER.ASSIGN_STAFF',
         P_TABLE_NAME    => 'ABSH_VISIT_WORKER_ASSIGNMENTS'
      );

      V_RESULT_RAW := GET_STAFF(P_INDV_RFQ_ID, P_ONE_SCHED_ID, P_SERVICE_AREA_ID);

      IF V_RESULT_RAW LIKE 'OK|%' THEN
         V_STAFF_ID   := TO_NUMBER(SUBSTR(V_RESULT_RAW, INSTR(V_RESULT_RAW, '=') + 1));
         V_STAFF_ROLE := 'Worker';

         V_STEP := 'INSERT_ASSIGNMENT';
         INSERT INTO ABSH_VISIT_WORKER_ASSIGNMENTS
            (SCHEDULE_ID, STAFF_ID, ROLE)
         VALUES
            (P_ONE_SCHED_ID, V_STAFF_ID, V_STAFF_ROLE);

         V_STEP := 'MERGE_LOAD';
         MERGE INTO ABSH_STAFF_LOAD L
         USING DUAL
         ON (L.STAFF_ID = V_STAFF_ID)
         WHEN MATCHED THEN
            UPDATE SET L.TOTAL_ORDERS = NVL(L.TOTAL_ORDERS, 0) + 1
         WHEN NOT MATCHED THEN
            INSERT (STAFF_ID, TOTAL_ORDERS) VALUES (V_STAFF_ID, 1);

         ABSH_UTIL_PKG.LOG_ERROR(
            P_ERROR_MESSAGE => '[INFO] Staff assigned successfully | Staff_ID: ' || V_STAFF_ID || ' | RFQ_ID: ' || P_INDV_RFQ_ID || ' | Schedule_ID: ' || P_ONE_SCHED_ID || ' | Role: ' || V_STAFF_ROLE,
            P_CALLING_PROC  => 'ABSH_CREATE_ORDER.ASSIGN_STAFF',
            P_TABLE_NAME    => 'ABSH_VISIT_WORKER_ASSIGNMENTS'
         );

         V_STEP   := 'DONE';
         V_RESULT := V_RESULT_RAW;
      ELSE
         V_STEP := 'FAIL_GET_STAFF';
         ABSH_UTIL_PKG.LOG_ERROR(
            P_ERROR_MESSAGE => '[ERROR] no Assign_staff select | RFQ_ID: ' || P_INDV_RFQ_ID || ' | Schedule_ID: ' || P_ONE_SCHED_ID || ' | Result_Raw: ' || V_RESULT_RAW,
            P_ERROR_CODE    => 'NO_STAFF_FOUND',
            P_CALLING_PROC  => 'ABSH_CREATE_ORDER.ASSIGN_STAFF',
            P_TABLE_NAME    => 'ABSH_STAFF'
         );

         RAISE_APPLICATION_ERROR(-20001, 'GET_staff failed: ' || V_RESULT_RAW);
         V_RESULT := 'لم يتم تعيين موظفين';

         INSERT INTO ABSH_VISIT_WORKER_ASSIGNMENTS (SCHEDULE_ID, STAFF_ID, ROLE) VALUES (P_ONE_SCHED_ID, NULL, NULL);
      END IF;

      RETURN V_RESULT;

   EXCEPTION
      WHEN OTHERS THEN
         ABSH_UTIL_PKG.LOG_ERROR(
            P_ERROR_MESSAGE => '[ERROR] Assign_staff exception | RFQ_ID: ' || P_INDV_RFQ_ID || ' | Schedule_ID: ' || P_ONE_SCHED_ID || ' | STEP: ' || V_STEP || ' | Error: ' || SQLERRM,
            P_ERROR_CODE    => SQLCODE,
            P_ERROR_STACK   => DBMS_UTILITY.FORMAT_ERROR_BACKTRACE,
            P_CALLING_PROC  => 'ABSH_CREATE_ORDER.ASSIGN_STAFF',
            P_TABLE_NAME    => 'ABSH_VISIT_WORKER_ASSIGNMENTS'
         );
         RAISE;
   END ASSIGN_STAFF;

   FUNCTION GET_RANDOM_STAFF(P_INDV_RFQ_ID IN NUMBER) RETURN VARCHAR2 IS
      V_STAFF_ID   NUMBER;
      V_STAFF_ROLE VARCHAR2(100);
      V_RESULT     VARCHAR2(200);
   BEGIN
      BEGIN
         SELECT STAFF_ID, ROLE
           INTO V_STAFF_ID, V_STAFF_ROLE
           FROM (SELECT ST.STAFF_ID, ST.ROLE
                   FROM RUNERP_CUSTDATA.ABSH_STAFF ST
                  WHERE ST.ROLE = 'Worker'
                    AND ST.STATUS = 'ACTIVE'
                    AND ST.STAFF_ID NOT IN
                        (SELECT A.STAFF_ID
                           FROM ABSH_VISIT_WORKER_ASSIGNMENTS A
                           JOIN ABSH_VISIT_SCHEDULE S ON A.SCHEDULE_ID = S.SCHEDULE_ID
                          WHERE S.INDV_RFQ_ID = P_INDV_RFQ_ID
                            AND TRUNC(S.VISIT_DATE) = TRUNC((SELECT VISIT_DATE
                                                              FROM ABSH_VISIT_SCHEDULE
                                                             WHERE INDV_RFQ_ID = P_INDV_RFQ_ID
                                                             FETCH FIRST 1 ROWS ONLY)))
                  ORDER BY DBMS_RANDOM.VALUE)
          WHERE ROWNUM = 1;

         V_RESULT := V_STAFF_ID || ':' || V_STAFF_ROLE;

      EXCEPTION
         WHEN NO_DATA_FOUND THEN
            V_RESULT := NULL;
      END;

      RETURN V_RESULT;

   EXCEPTION
      WHEN OTHERS THEN
         RETURN NULL;
   END GET_RANDOM_STAFF;

   PROCEDURE ADD_CUSTOMER_STAFF_PREF (
       P_CUSTOMER_ID IN NUMBER,
       P_WORKER_ID   IN NUMBER,
       P_PREF_TYPE   IN VARCHAR2   -- 'PREFERRED' or 'BLOCKED'
      ) IS
    BEGIN
       IF P_PREF_TYPE NOT IN ('PREFERRED', 'BLOCKED') THEN
          RAISE_APPLICATION_ERROR(-20001, 'Invalid PREF_TYPE. Must be PREFERRED or BLOCKED.');
       END IF;

       MERGE INTO ABSH_CUSTOMER_STAFF_PREF T
       USING (SELECT P_CUSTOMER_ID AS CUSTOMER_ID,
                     P_WORKER_ID   AS WORKER_ID,
                     P_PREF_TYPE   AS PREF_TYPE
                FROM DUAL) S
       ON (T.CUSTOMER_ID = S.CUSTOMER_ID AND T.WORKER_ID = S.WORKER_ID)
       WHEN MATCHED THEN
          UPDATE SET T.PREF_TYPE     = S.PREF_TYPE,
                     T.CREATED_DATE  = SYSDATE
       WHEN NOT MATCHED THEN
          INSERT (CUSTOMER_ID, WORKER_ID, PREF_TYPE, CREATED_DATE)
          VALUES (S.CUSTOMER_ID, S.WORKER_ID, S.PREF_TYPE, SYSDATE);

       -- COMMIT REMOVED. Transaction control is deferred to the API caller boundary.

    EXCEPTION
       WHEN OTHERS THEN
          -- ROLLBACK REMOVED. Raising exception and letting caller control transaction.
          ABSH_UTIL_PKG.LOG_ERROR(
             P_ERROR_MESSAGE => 'Failed to add customer staff preference. Customer ID: ' || P_CUSTOMER_ID || ', Worker ID: ' || P_WORKER_ID || ', Preference: ' || P_PREF_TYPE,
             P_ERROR_CODE    => SQLCODE,
             P_ERROR_STACK   => DBMS_UTILITY.FORMAT_ERROR_BACKTRACE,
             P_CALLING_PROC  => 'ABSH_CREATE_ORDER.ADD_CUSTOMER_STAFF_PREF',
             P_TABLE_NAME    => 'ABSH_CUSTOMER_STAFF_PREF'
          );
          RAISE;
   END ADD_CUSTOMER_STAFF_PREF;

 FUNCTION GET_STAFF (
     P_INDV_RFQ_ID     IN NUMBER,
     P_ONE_SCHED_ID    IN NUMBER,
     P_SERVICE_AREA_ID IN NUMBER
  ) RETURN VARCHAR2 IS
     V_STAFF_ID    NUMBER;
     V_LOCATIONS   VARCHAR2(4000);
     V_SHIFT_ID    NUMBER;
     V_VISIT_DATE  DATE;
     V_START_TIME  VARCHAR2(5);
     V_END_TIME    VARCHAR2(5);
     V_STAFF_ROLE  VARCHAR2(100);
     V_CUSTOMER_ID NUMBER;
     V_STEP        VARCHAR2(100);
     V_TRACE       VARCHAR2(4000);
     V_PREF_TOTAL       NUMBER := 0;
     V_PREF_SHIFT_OK    NUMBER := 0;
     V_PREF_CAL_OK      NUMBER := 0;
     V_PREF_FREE        NUMBER := 0;

  BEGIN
     ------------------------------------------------------------------
     V_STEP  := 'LOAD_SCHEDULE';
     V_TRACE := '[TRACE] sched_id=' || P_ONE_SCHED_ID
             || ' | rfq_id='        || P_INDV_RFQ_ID
             || ' | area_id='       || P_SERVICE_AREA_ID;

     SELECT VISIT_DATE, START_TIME, END_TIME, SHIFT_ID
       INTO V_VISIT_DATE, V_START_TIME, V_END_TIME, V_SHIFT_ID
       FROM ABSH_VISIT_SCHEDULE
      WHERE SCHEDULE_ID = P_ONE_SCHED_ID;

     V_TRACE := V_TRACE
             || ' | visit_date=' || TO_CHAR(V_VISIT_DATE, 'YYYY-MM-DD')
             || ' | time='       || V_START_TIME || '-' || V_END_TIME
             || ' | shift_id='   || V_SHIFT_ID;

     ------------------------------------------------------------------
     V_STEP := 'GET_CUSTOMER';

     BEGIN
        SELECT CUSTOMER_ID
          INTO V_CUSTOMER_ID
          FROM INDV_SAL_RFQ
         WHERE INDV_RFQ_ID = P_INDV_RFQ_ID;
     EXCEPTION
        WHEN NO_DATA_FOUND THEN
           V_CUSTOMER_ID := NULL;
     END;

     V_TRACE := V_TRACE || ' | customer_id=' || NVL(TO_CHAR(V_CUSTOMER_ID), 'NULL');

     ------------------------------------------------------------------
     V_STEP := 'GET_LOCATION';

     BEGIN
        SELECT LISTAGG(C.LOCATION_NAME_L1, ' , ') WITHIN GROUP(ORDER BY A.PRIORITY)
          INTO V_LOCATIONS
          FROM ABSH_SERVICE_AREA_CAMPS A
          JOIN CMP_LOCATIONS C ON C.LOCATION_ID = A.CAMP_ID
         WHERE A.SERVICE_AREA_ID = P_SERVICE_AREA_ID
         FETCH FIRST 1 ROWS ONLY;
     EXCEPTION
        WHEN NO_DATA_FOUND THEN
           ABSH_UTIL_PKG.LOG_ERROR(
              P_ERROR_MESSAGE => V_TRACE || ' | STEP=GET_LOCATION | No camp found | area=' || P_SERVICE_AREA_ID,
              P_ERROR_CODE    => 'NO_CAMP_FOUND',
              P_ERROR_STACK   => V_STEP,
              P_CALLING_PROC  => 'ABSH_CREATE_ORDER.GET_STAFF',
              P_TABLE_NAME    => 'ABSH_SERVICE_AREA_CAMPS'
           );
           RETURN '[GET_STAFF] No camp found for service area=' || P_SERVICE_AREA_ID;
     END;

     V_TRACE := V_TRACE || ' | locations=' || V_LOCATIONS;

     ------------------------------------------------------------------
     V_STEP := 'GET_STAFF_PREFERRED';

     IF V_CUSTOMER_ID IS NOT NULL THEN
        SELECT COUNT(*)
          INTO V_PREF_TOTAL
          FROM ABSH_SERVICE_AREA_CAMPS C
          JOIN ABSH_STAFF              S ON S.LOCATION_ID = C.CAMP_ID
          JOIN ABSH_CUSTOMER_STAFF_PREF P ON P.WORKER_ID  = S.WORKER_ID
                                         AND P.CUSTOMER_ID = V_CUSTOMER_ID
                                         AND P.PREF_TYPE   = 'PREFERRED'
         WHERE C.SERVICE_AREA_ID = P_SERVICE_AREA_ID
           AND S.ROLE             = 'Worker'
           AND S.STATUS           = 'ACTIVE';

        SELECT COUNT(*)
          INTO V_PREF_SHIFT_OK
          FROM ABSH_SERVICE_AREA_CAMPS C
          JOIN ABSH_STAFF              S ON S.LOCATION_ID = C.CAMP_ID
          JOIN ABSH_CUSTOMER_STAFF_PREF P ON P.WORKER_ID  = S.WORKER_ID
                                         AND P.CUSTOMER_ID = V_CUSTOMER_ID
                                         AND P.PREF_TYPE   = 'PREFERRED'
         WHERE C.SERVICE_AREA_ID   = P_SERVICE_AREA_ID
           AND S.ROLE               = 'Worker'
           AND S.STATUS             = 'ACTIVE'
           AND (S.SHIFTS = '0' OR S.SHIFTS = TO_CHAR(V_SHIFT_ID));

        SELECT COUNT(*)
          INTO V_PREF_CAL_OK
          FROM ABSH_SERVICE_AREA_CAMPS C
          JOIN ABSH_STAFF              S ON S.LOCATION_ID = C.CAMP_ID
          JOIN ABSH_CUSTOMER_STAFF_PREF P ON P.WORKER_ID  = S.WORKER_ID
                                         AND P.CUSTOMER_ID = V_CUSTOMER_ID
                                         AND P.PREF_TYPE   = 'PREFERRED'
         WHERE C.SERVICE_AREA_ID   = P_SERVICE_AREA_ID
           AND S.ROLE               = 'Worker'
           AND S.STATUS             = 'ACTIVE'
           AND (S.SHIFTS = '0' OR S.SHIFTS = TO_CHAR(V_SHIFT_ID))
           AND IS_STAFF_AVAILABLE_BY_CALENDAR(S.STAFF_ID, V_VISIT_DATE) = 1;

        SELECT COUNT(*)
          INTO V_PREF_FREE
          FROM ABSH_SERVICE_AREA_CAMPS C
          JOIN ABSH_STAFF              S ON S.LOCATION_ID = C.CAMP_ID
          JOIN ABSH_CUSTOMER_STAFF_PREF P ON P.WORKER_ID  = S.WORKER_ID
                                         AND P.CUSTOMER_ID = V_CUSTOMER_ID
                                         AND P.PREF_TYPE   = 'PREFERRED'
         WHERE C.SERVICE_AREA_ID   = P_SERVICE_AREA_ID
           AND S.ROLE               = 'Worker'
           AND S.STATUS             = 'ACTIVE'
           AND (S.SHIFTS = '0' OR S.SHIFTS = TO_CHAR(V_SHIFT_ID))
           AND IS_STAFF_AVAILABLE_BY_CALENDAR(S.STAFF_ID, V_VISIT_DATE) = 1
           AND NOT EXISTS (
                  SELECT 1
                    FROM ABSH_VISIT_WORKER_ASSIGNMENTS A
                    JOIN ABSH_VISIT_SCHEDULE            V ON V.SCHEDULE_ID = A.SCHEDULE_ID
                   WHERE A.STAFF_ID = S.STAFF_ID
                     AND TRUNC(V.VISIT_DATE) = TRUNC(V_VISIT_DATE)
                     AND (CASE WHEN REGEXP_LIKE(V.START_TIME, '^\d{2}:\d{2}$')
                               THEN TO_DATE(V.START_TIME, 'HH24:MI') END)
                         < TO_DATE(V_END_TIME, 'HH24:MI')
                     AND (CASE WHEN REGEXP_LIKE(V.END_TIME, '^\d{2}:\d{2}$')
                               THEN TO_DATE(V.END_TIME, 'HH24:MI') END)
                         > TO_DATE(V_START_TIME, 'HH24:MI')
               );

        V_TRACE := V_TRACE
                || ' | PREF_TOTAL='    || V_PREF_TOTAL
                || ' | PREF_SHIFT_OK=' || V_PREF_SHIFT_OK
                || ' | PREF_CAL_OK='   || V_PREF_CAL_OK
                || ' | PREF_FREE='     || V_PREF_FREE;

        IF V_PREF_FREE > 0 THEN
           BEGIN
              SELECT STAFF_ID, ROLE
                INTO V_STAFF_ID, V_STAFF_ROLE
                FROM (
                       SELECT S.STAFF_ID,
                              S.ROLE,
                              NVL(L.TOTAL_ORDERS, 0) AS TOTAL_ORDERS,
                              C.PRIORITY              AS CAMP_PRIORITY
                         FROM ABSH_SERVICE_AREA_CAMPS  C
                         JOIN ABSH_STAFF               S ON S.LOCATION_ID = C.CAMP_ID
                         JOIN ABSH_CUSTOMER_STAFF_PREF P ON P.WORKER_ID  = S.WORKER_ID
                                                        AND P.CUSTOMER_ID  = V_CUSTOMER_ID
                                                        AND P.PREF_TYPE    = 'PREFERRED'
                         LEFT JOIN ABSH_STAFF_LOAD     L ON L.STAFF_ID    = S.STAFF_ID
                        WHERE C.SERVICE_AREA_ID = P_SERVICE_AREA_ID
                          AND S.ROLE            = 'Worker'
                          AND S.STATUS          = 'ACTIVE'
                          AND (S.SHIFTS = '0' OR S.SHIFTS = TO_CHAR(V_SHIFT_ID))
                          AND IS_STAFF_AVAILABLE_BY_CALENDAR(S.STAFF_ID, V_VISIT_DATE) = 1
                          AND NOT EXISTS (
                                 SELECT 1
                                   FROM ABSH_VISIT_WORKER_ASSIGNMENTS A
                                   JOIN ABSH_VISIT_SCHEDULE            V ON V.SCHEDULE_ID = A.SCHEDULE_ID
                                  WHERE A.STAFF_ID = S.STAFF_ID
                                    AND TRUNC(V.VISIT_DATE) = TRUNC(V_VISIT_DATE)
                                    AND (CASE WHEN REGEXP_LIKE(V.START_TIME, '^\d{2}:\d{2}$')
                                              THEN TO_DATE(V.START_TIME, 'HH24:MI') END)
                                        < TO_DATE(V_END_TIME, 'HH24:MI')
                                    AND (CASE WHEN REGEXP_LIKE(V.END_TIME, '^\d{2}:\d{2}$')
                                              THEN TO_DATE(V.END_TIME, 'HH24:MI') END)
                                        > TO_DATE(V_START_TIME, 'HH24:MI')
                             )
                      )
                ORDER BY CAMP_PRIORITY ASC, TOTAL_ORDERS ASC
                FETCH FIRST 1 ROWS ONLY;

              -- Log success autonomously without transaction-breaking COMMIT
              ABSH_UTIL_PKG.LOG_ERROR(
                 P_ERROR_MESSAGE => V_TRACE || ' | RESULT=PREFERRED_FOUND | staff_id=' || V_STAFF_ID,
                 P_ERROR_CODE    => 'PREFERRED_FOUND',
                 P_ERROR_STACK   => 'SUCCESS',
                 P_CALLING_PROC  => 'ABSH_CREATE_ORDER.GET_STAFF',
                 P_TABLE_NAME    => 'ABSH_STAFF'
              );

              RETURN 'OK|STAFF_ID=' || V_STAFF_ID;

           EXCEPTION
              WHEN NO_DATA_FOUND THEN NULL;
           END;
        ELSE
           DECLARE
              V_REASON VARCHAR2(500) := 'PREF_NOT_FOUND: ';
           BEGIN
              IF V_PREF_TOTAL = 0 THEN
                 V_REASON := V_REASON || 'لا يوجد عمال مفضلين للكاستمر في المنطقة دي';
              ELSIF V_PREF_SHIFT_OK = 0 THEN
                 V_REASON := V_REASON || 'العمال المفضلين شيفتهم مش مظبوطة (shift_id=' || V_SHIFT_ID || ')';
              ELSIF V_PREF_CAL_OK = 0 THEN
                 V_REASON := V_REASON || 'العمال المفضلين مش متاحين في التقويم (visit_date=' || TO_CHAR(V_VISIT_DATE,'YYYY-MM-DD') || ')';
              ELSE
                 V_REASON := V_REASON || 'العمال المفضلين كلهم محجوزين في نفس الوقت (' || V_START_TIME || '-' || V_END_TIME || ')';
              END IF;
              V_TRACE := V_TRACE || ' | ' || V_REASON;
           END;
        END IF;
     ELSE
        V_TRACE := V_TRACE || ' | PREF_SKIP: customer_id=NULL لا يوجد كاستمر مرتبط بالـ RFQ';
     END IF;

     ------------------------------------------------------------------
     V_STEP := 'GET_STAFF_GENERAL';

     BEGIN
        SELECT STAFF_ID, ROLE
          INTO V_STAFF_ID, V_STAFF_ROLE
          FROM (
                 SELECT S.STAFF_ID,
                        S.ROLE,
                        NVL(L.TOTAL_ORDERS, 0) AS TOTAL_ORDERS,
                        C.PRIORITY              AS CAMP_PRIORITY
                   FROM ABSH_SERVICE_AREA_CAMPS  C
                   JOIN ABSH_STAFF               S  ON S.LOCATION_ID = C.CAMP_ID
                   LEFT JOIN ABSH_STAFF_LOAD     L  ON L.STAFF_ID    = S.STAFF_ID
                  WHERE C.SERVICE_AREA_ID = P_SERVICE_AREA_ID
                    AND S.ROLE            = 'Worker'
                    AND S.STATUS          = 'ACTIVE'
                    AND (S.SHIFTS = '0' OR S.SHIFTS = TO_CHAR(V_SHIFT_ID))
                    AND IS_STAFF_AVAILABLE_BY_CALENDAR(S.STAFF_ID, V_VISIT_DATE) = 1
                    AND NOT EXISTS (
                           SELECT 1
                             FROM ABSH_CUSTOMER_STAFF_PREF P
                            WHERE P.CUSTOMER_ID = V_CUSTOMER_ID
                              AND P.WORKER_ID   = S.WORKER_ID
                              AND P.PREF_TYPE   = 'BLOCKED'
                        )
                    AND NOT EXISTS (
                           SELECT 1
                             FROM ABSH_VISIT_WORKER_ASSIGNMENTS A
                             JOIN ABSH_VISIT_SCHEDULE            V ON V.SCHEDULE_ID = A.SCHEDULE_ID
                            WHERE A.STAFF_ID = S.STAFF_ID
                              AND TRUNC(V.VISIT_DATE) = TRUNC(V_VISIT_DATE)
                              AND (CASE WHEN REGEXP_LIKE(V.START_TIME, '^\d{2}:\d{2}$')
                                        THEN TO_DATE(V.START_TIME, 'HH24:MI') END)
                                  < TO_DATE(V_END_TIME, 'HH24:MI')
                              AND (CASE WHEN REGEXP_LIKE(V.END_TIME, '^\d{2}:\d{2}$')
                                        THEN TO_DATE(V.END_TIME, 'HH24:MI') END)
                                  > TO_DATE(V_START_TIME, 'HH24:MI')
                        )
               )
           ORDER BY CAMP_PRIORITY ASC, TOTAL_ORDERS ASC
           FETCH FIRST 1 ROWS ONLY;

        -- Log general found autonomously
        ABSH_UTIL_PKG.LOG_ERROR(
           P_ERROR_MESSAGE => V_TRACE || ' | RESULT=GENERAL_FOUND | staff_id=' || V_STAFF_ID,
           P_ERROR_CODE    => 'GENERAL_FOUND',
           P_ERROR_STACK   => 'SUCCESS',
           P_CALLING_PROC  => 'ABSH_CREATE_ORDER.GET_STAFF',
           P_TABLE_NAME    => 'ABSH_STAFF'
        );

     EXCEPTION
        WHEN NO_DATA_FOUND THEN
           -- Log no staff autonomously
           ABSH_UTIL_PKG.LOG_ERROR(
              P_ERROR_MESSAGE => V_TRACE || ' | RESULT=NO_STAFF_FOUND',
              P_ERROR_CODE    => 'NO_STAFF_FOUND',
              P_ERROR_STACK   => V_STEP,
              P_CALLING_PROC  => 'ABSH_CREATE_ORDER.GET_STAFF',
              P_TABLE_NAME    => 'ABSH_STAFF'
           );

           RETURN '[GET_STAFF] No available staff | ' || V_LOCATIONS
                  || ' | area=' || P_SERVICE_AREA_ID
                  || ' | time=' || V_START_TIME || '-' || V_END_TIME;
     END;

     RETURN 'OK|STAFF_ID=' || V_STAFF_ID;

  EXCEPTION
     WHEN OTHERS THEN
        -- Log fatal autonomously
        ABSH_UTIL_PKG.LOG_ERROR(
           P_ERROR_MESSAGE => V_TRACE || ' | FATAL STEP=' || V_STEP || ' | Error: ' || SQLERRM,
           P_ERROR_CODE    => SQLCODE,
           P_ERROR_STACK   => DBMS_UTILITY.FORMAT_ERROR_BACKTRACE,
           P_CALLING_PROC  => 'ABSH_CREATE_ORDER.GET_STAFF',
           P_TABLE_NAME    => 'ABSH_STAFF'
        );

        RETURN 'ERR|STEP=' || V_STEP
            || '|ERR_CODE=' || SQLCODE
            || '|ERR_MSG='  || SUBSTR(SQLERRM, 1, 200);
  END GET_STAFF;
   ----------------------------------------------------------------------------------
   FUNCTION IS_STAFF_AVAILABLE_BY_CALENDAR
   (
      P_STAFF_ID   IN NUMBER
     ,P_VISIT_DATE IN DATE
   ) RETURN NUMBER IS
      V_CALENDAR_ID ABSH_STAFF.CALENDAR_ID%TYPE;
      V_CNT         NUMBER;
   BEGIN
      SELECT CALENDAR_ID INTO V_CALENDAR_ID FROM ABSH_STAFF WHERE STAFF_ID = P_STAFF_ID;

      IF V_CALENDAR_ID IS NULL THEN
         RETURN 1;
      END IF;

      SELECT COUNT(*)
        INTO V_CNT
        FROM ABSH_CALENDARS CAL
        JOIN TABLE(APEX_STRING.SPLIT(CAL.CALENDAR_DAYS, ':')) D ON CAL.CALENDAR_ID = V_CALENDAR_ID
       WHERE TRIM(UPPER(D.COLUMN_VALUE)) = TRIM(UPPER(TO_CHAR(P_VISIT_DATE, 'DAY', 'NLS_DATE_LANGUAGE=ENGLISH')));

      IF V_CNT > 0 THEN
         RETURN 1;
      ELSE
         RETURN 0;
      END IF;

   EXCEPTION
      WHEN NO_DATA_FOUND THEN
         RETURN 0;
      WHEN OTHERS THEN
         RETURN 0;
   END IS_STAFF_AVAILABLE_BY_CALENDAR;

   FUNCTION GET_STAFF_STATUS(P_WORKER_ID NUMBER) RETURN VARCHAR2 IS
   BEGIN
      IF CMP_CAMP_OCCUPANCY_PKG.IS_EMP_AVAILABLE_FOR_RENT(P_WORKER_ID) = 'YES' THEN
         RETURN 'ACTIVE';
      ELSE
         RETURN 'INACTIVE';
      END IF;
   END;

   PROCEDURE SYNC_STAFF_FROM_HR(P_WORKER_ID NUMBER) IS
   BEGIN
      UPDATE ABSH_STAFF S
         SET S.STATUS      = GET_STAFF_STATUS(P_WORKER_ID)
            ,S.LOCATION_ID = (SELECT O.LOCATION_ID
                              FROM RUNERP_CUSTDATA.CMP_CAMP_OCCUPANCY O
                              WHERE O.EMP_ID = S.WORKER_ID
                                AND O.CHECK_OUT IS NULL
                                AND ROWNUM = 1)
            ,S.UPDATED_AT  = SYSDATE
       WHERE S.WORKER_ID = P_WORKER_ID;
   END;

   PROCEDURE SYNC_ALL_STAFF_FROM_HR IS
      V_FUN CLOB;
   BEGIN
      ------------------------------------------------------------------
      -- 1 Sync Staff Status & Location
      ------------------------------------------------------------------
      UPDATE ABSH_STAFF S
         SET STATUS      = GET_STAFF_STATUS(S.WORKER_ID)
            ,LOCATION_ID = (SELECT O.LOCATION_ID
                            FROM RUNERP_CUSTDATA.CMP_CAMP_OCCUPANCY O
                            WHERE O.EMP_ID = S.WORKER_ID
                              AND O.CHECK_OUT IS NULL
                              AND ROWNUM = 1)
            ,UPDATED_AT  = SYSDATE
       WHERE NVL(STATUS, 'X') <> GET_STAFF_STATUS(S.WORKER_ID)
          OR NVL(LOCATION_ID, -1) <> NVL((SELECT O.LOCATION_ID
                                          FROM RUNERP_CUSTDATA.CMP_CAMP_OCCUPANCY O
                                          WHERE O.EMP_ID = S.WORKER_ID
                                            AND O.CHECK_OUT IS NULL
                                            AND ROWNUM = 1), -1);

      ------------------------------------------------------------------
      -- 2 Cancel future assignments for INACTIVE staff
      ------------------------------------------------------------------
      UPDATE ABSH_VISIT_WORKER_ASSIGNMENTS A
         SET A.STATUS        = 'CANCELLED'
            ,A.IS_REASSIGNED = 0
            ,A.UPDATED_AT    = SYSDATE
       WHERE A.STATUS = 'ASSIGNED'
         AND EXISTS (SELECT 1
                FROM ABSH_STAFF S
                JOIN ABSH_VISIT_SCHEDULE V ON V.SCHEDULE_ID = A.SCHEDULE_ID
               WHERE S.STAFF_ID = A.STAFF_ID
                 AND S.STATUS = 'INACTIVE'
                 AND V.VISIT_DATE >= TRUNC(SYSDATE));

      ------------------------------------------------------------------
      -- Log cancelled staff
      ------------------------------------------------------------------
      INSERT INTO ABSH_SYNC_LOG
         (STAFF_ID, ACTION, ACTION_DATE)
         SELECT S.STAFF_ID, 'CANCEL_VISITS', SYSDATE FROM ABSH_STAFF S WHERE S.STATUS = 'INACTIVE';

      ------------------------------------------------------------------
      -- Re-assign staff to affected visits
      ------------------------------------------------------------------
      FOR R IN (SELECT V.SCHEDULE_ID, V.INDV_RFQ_ID, A.STAFF_ID, V.ADDRESS_ID, SA.SERVICE_AREA_ID
                  FROM ABSH_VISIT_SCHEDULE V

                  JOIN ABSH_VISIT_WORKER_ASSIGNMENTS A ON A.SCHEDULE_ID = V.SCHEDULE_ID
                  JOIN ABSH_STAFF F ON F.STAFF_ID = A.STAFF_ID
                  JOIN ABSH_CUSTOMER_ADDRESSES D ON D.ADDRESS_ID = V.ADDRESS_ID
                  JOIN ABSH_SERVICE_AREA_CAMPS SA ON SA.SERVICE_AREA_ID = D.SERVICE_AREA_ID
                                                 AND SA.CAMP_ID = F.LOCATION_ID

                 WHERE V.VISIT_DATE >= TRUNC(SYSDATE)
                   AND A.STATUS = 'CANCELLED'
                   AND NVL(A.IS_REASSIGNED, 0) = 0
                   AND NOT EXISTS (SELECT 1
                          FROM ABSH_VISIT_WORKER_ASSIGNMENTS X
                          JOIN ABSH_STAFF S ON S.STAFF_ID = X.STAFF_ID
                         WHERE X.SCHEDULE_ID = V.SCHEDULE_ID
                           AND X.STAFF_ID = A.STAFF_ID
                           AND X.STATUS = 'ASSIGNED'
                           AND S.STATUS = 'ACTIVE')) LOOP
         BEGIN
            V_FUN := ASSIGN_STAFF(P_INDV_RFQ_ID     => R.INDV_RFQ_ID,
                                  P_ONE_SCHED_ID    => R.SCHEDULE_ID,
                                  P_SERVICE_AREA_ID => R.SERVICE_AREA_ID);

            INSERT INTO ABSH_SYNC_LOG
               (ACTION, STAFF_ID, ACTION_DATE, NOTES)
            VALUES
               ('REASSIGN_STAFF', R.STAFF_ID, SYSDATE, 'Schedule=' || R.SCHEDULE_ID);

            UPDATE ABSH_VISIT_WORKER_ASSIGNMENTS
               SET STATUS        = 'CANCELLED'
                  ,IS_REASSIGNED = 1
                  ,UPDATED_AT    = CURRENT_TIMESTAMP
             WHERE SCHEDULE_ID = R.SCHEDULE_ID
               AND STAFF_ID = R.STAFF_ID
               AND STATUS = 'CANCELLED';

         EXCEPTION
            WHEN OTHERS THEN
               INSERT INTO ABSH_EXCEPTION_LOG
                  (ERROR_MESSAGE)
               VALUES
                  ('[SYNC_REASSIGN_ERROR] sched_id=' || R.SCHEDULE_ID || ' | ' || ' | trace=' ||
                   DBMS_UTILITY.FORMAT_ERROR_BACKTRACE);
         END;
      END LOOP;

   END;
   FUNCTION GET_SERVICE_AREA_ID(P_INDV_RFQ_ID IN NUMBER) RETURN NUMBER IS
      V_SERVICE_AREA_ID NUMBER;
   BEGIN
      SELECT DISTINCT SERVICE_AREA_ID
        INTO V_SERVICE_AREA_ID
        FROM ABSH_PACKAGE_AREAS
       WHERE PACKAGE_ID = (SELECT INDV_SAL_QUOT_ID FROM INDV_SAL_RFQ WHERE INDV_RFQ_ID = P_INDV_RFQ_ID);

      RETURN V_SERVICE_AREA_ID;

   EXCEPTION
      WHEN NO_DATA_FOUND THEN
         RETURN NULL;
      WHEN TOO_MANY_ROWS THEN
         RETURN NULL;
      WHEN OTHERS THEN
         RETURN NULL;
   END GET_SERVICE_AREA_ID;

   FUNCTION GET_NATIONALITY_NAME(P_NATIONALITY_ID NUMBER) RETURN VARCHAR2 IS
      CURSOR C_NATIONALITY__NAME_CUR IS
         SELECT COUNTRY_NAME_L1 FROM RUNERP_SYSDATA.SM_COUNTRY WHERE COUNTRY_ID = P_NATIONALITY_ID;
   BEGIN
      FOR C_NATIONALITY_REC IN C_NATIONALITY__NAME_CUR LOOP
         RETURN C_NATIONALITY_REC.COUNTRY_NAME_L1;
      END LOOP;
      RETURN NULL;
   END;

   FUNCTION GET_CAMP_NAME(P_LOCATION_ID NUMBER) RETURN VARCHAR2 IS
      CURSOR C_CAMP_NAME_CUR IS
         SELECT LOCATION_NAME_L1 FROM CMP_LOCATIONS WHERE LOCATION_ID = P_LOCATION_ID;
   BEGIN
      FOR C_CAMP_REC IN C_CAMP_NAME_CUR LOOP
         RETURN C_CAMP_REC.LOCATION_NAME_L1;
      END LOOP;
      RETURN NULL;
   END GET_CAMP_NAME;

   FUNCTION GET_CHILD_FK_DETAILS(P_PARENT_TABLE VARCHAR2) RETURN CLOB IS
      L_JSON  CLOB := '[';
      L_FIRST BOOLEAN := TRUE;
   BEGIN
      FOR R IN (SELECT A.CONSTRAINT_NAME, A.TABLE_NAME AS CHILD_TABLE, P.TABLE_NAME AS PARENT_TABLE, A.DELETE_RULE
                  FROM ALL_CONSTRAINTS A
                  JOIN ALL_CONSTRAINTS P ON A.R_CONSTRAINT_NAME = P.CONSTRAINT_NAME
                 WHERE A.CONSTRAINT_TYPE = 'R'
                   AND P.TABLE_NAME = UPPER(P_PARENT_TABLE)) LOOP
         IF NOT L_FIRST THEN
            L_JSON := L_JSON || ',';
         END IF;

         L_JSON := L_JSON || '{' || '"child_table":"' || R.CHILD_TABLE || '",' || '"constraint_name":"' ||
                   R.CONSTRAINT_NAME || '",' || '"delete_rule":"' || R.DELETE_RULE || '"' || '}';

         L_FIRST := FALSE;
      END LOOP;

      L_JSON := L_JSON || ']';

      RETURN L_JSON;
   END;

   FUNCTION SADAD_PAY_ORDER RETURN VARCHAR2 IS
   BEGIN
      RETURN C_SUCCESS;
   END;

   -- ==================================================
   -- AUTONOMOUS LOGGING PROCEDURE
   -- ==================================================
   PROCEDURE LOG_ERROR(P_MESSAGE IN VARCHAR2) AS
   BEGIN
      ABSH_UTIL_PKG.LOG_ERROR(
         P_ERROR_MESSAGE => P_MESSAGE,
         P_CALLING_PROC  => 'ABSH_CREATE_ORDER'
      );
   END LOG_ERROR;

   PROCEDURE HANDLE_ERROR
   (
      P_STEP    IN VARCHAR2
     ,P_CONTEXT IN VARCHAR2
     ,P_STATUS  OUT VARCHAR2
     ,P_MESSAGE OUT VARCHAR2
   ) AS
      L_ERROR_MSG VARCHAR2(4000);
   BEGIN
      L_ERROR_MSG := SQLERRM;
      P_STATUS    := C_ERROR;
      P_MESSAGE   := 'خطأ في المرحلة: ' || P_STEP || ' - ' || SUBSTR(L_ERROR_MSG, 1, 200);

      ABSH_UTIL_PKG.LOG_ERROR(
         P_ERROR_MESSAGE => P_CONTEXT || ' | STEP=' || P_STEP || ' | Error Message: ' || L_ERROR_MSG,
         P_ERROR_CODE    => SQLCODE,
         P_ERROR_STACK   => DBMS_UTILITY.FORMAT_ERROR_BACKTRACE,
         P_CALLING_PROC  => 'ABSH_CREATE_ORDER'
      );
   END HANDLE_ERROR;


   -- ==================================================
   -- 1. Create initial order (pre-payment) in RFQ table
   -- ==================================================
   PROCEDURE CREATE_INITIAL_RFQ
   (
      P_CUST_SITE_ID          IN VARCHAR2 DEFAULT NULL
     ,P_CUSTOMER_ID           IN NUMBER DEFAULT NULL
     ,P_POTENTIAL_CUSTOMER_ID IN NUMBER DEFAULT NULL
     ,P_PACKAGE_ID            IN NUMBER
     ,P_COMBINATION_CODE      IN VARCHAR2 DEFAULT NULL
     ,P_TOTAL_PRICE           IN NUMBER DEFAULT NULL
     ,P_QUOT_PRICE            IN NUMBER DEFAULT NULL
     ,P_VISIT_DATA_JSON       IN CLOB DEFAULT NULL
     ,P_ADDRESS_ID            IN NUMBER DEFAULT NULL
     ,P_ACTION_USER           IN NUMBER DEFAULT NULL
     ,P_WITH_OUT_DET          IN VARCHAR2
     ,P_RFQ_ID                OUT NUMBER
     ,P_STATUS                OUT VARCHAR2
     ,P_MESSAGE               OUT VARCHAR2
   ) AS
      V_PRICE       NUMBER;
      V_STEP        VARCHAR2(500);
      V_ACTION_USER NUMBER;
   BEGIN
      V_STEP := 'Input Validation';

      IF P_PACKAGE_ID IS NULL THEN
         P_STATUS  := C_ERROR;
         P_MESSAGE := 'معرف الباقة مطلوب';
         RETURN;
      END IF;

      IF P_WITH_OUT_DET NOT IN ('Y', 'N') THEN
         P_STATUS  := C_ERROR;
         P_MESSAGE := 'قيمة غير صحيحة لـ p_with_out_det (يجب أن تكون Y أو N)';
         RETURN;
      END IF;

      V_ACTION_USER := NVL(P_ACTION_USER, TO_NUMBER(V('SESSION_USER_ID')));

      -- Price Validation (only if with details)

      IF P_WITH_OUT_DET <> 'Y' THEN
         V_STEP := 'Price Validation';
         BEGIN
            SELECT PRICE
              INTO V_PRICE
              FROM ABSH_MAIN_PACKAGE_PRICING_OPTIONS
             WHERE INDV_SAL_QUOT_ID = P_PACKAGE_ID
               AND COMBINATION_CODE = P_COMBINATION_CODE;
         EXCEPTION
            WHEN NO_DATA_FOUND THEN
               P_STATUS  := C_ERROR;
               P_MESSAGE := 'الباقة المختارة غير موجودة';
               RETURN;
         END;

         IF V_PRICE <> P_TOTAL_PRICE THEN
            P_STATUS  := C_ERROR;
            P_MESSAGE := 'خطأ في السعر المحسوب (المتوقع: ' || V_PRICE || ', المُدخل: ' || P_TOTAL_PRICE || ')';
            RETURN;
         END IF;
      END IF;

      V_STEP := 'Insert RFQ';

      INSERT INTO INDV_SAL_RFQ
         (CUST_SITE_ID
         ,CUSTOMER_ID
         ,POTENTIAL_CUSTOMER_ID
         ,INDV_SAL_QUOT_ID
         ,RFQ_DATE
         ,ACTION_USER
         ,RFQ_SOURCE
         ,RFQ_STATUS)
      VALUES
         (P_CUST_SITE_ID
         ,P_CUSTOMER_ID
         ,P_POTENTIAL_CUSTOMER_ID
         ,P_PACKAGE_ID
         ,SYSTIMESTAMP
         ,V_ACTION_USER
         ,'COMPANY'
         ,C_STATUS_PENDING)
      RETURNING INDV_RFQ_ID INTO P_RFQ_ID;

      -- If without details, return success
      IF P_WITH_OUT_DET = 'Y' THEN
         P_STATUS  := C_SUCCESS;

         P_MESSAGE := 'تم تسجيل طلبك بنجاح. رقم الطلب: ' || P_RFQ_ID;

         LOG_ERROR('RFQ Created (No Details): RFQ_ID=' || P_RFQ_ID);
         RETURN;
      END IF;

      -- Insert RFQ Details
      V_STEP := 'Insert RFQ Details';

      INSERT INTO ABSH_DTL_INDV_SAL_RFQ
         (INDV_RFQ_ID, INDV_SAL_QUOT_ID, COMBINATION_CODE, PRICE, SCHEDULE_JSON, ADDRESS_ID)
      VALUES
         (P_RFQ_ID, P_PACKAGE_ID, P_COMBINATION_CODE, P_QUOT_PRICE, P_VISIT_DATA_JSON, P_ADDRESS_ID);

      P_STATUS  := C_SUCCESS;
      P_MESSAGE := 'تم تسجيل طلبك بنجاح. رقم الطلب: ' || P_RFQ_ID;

      LOG_ERROR('RFQ Created Successfully: RFQ_ID=' || P_RFQ_ID || ' | PACKAGE=' || P_PACKAGE_ID || ' | PRICE=' ||
                P_TOTAL_PRICE);

   EXCEPTION
      WHEN OTHERS THEN
         ROLLBACK;
         HANDLE_ERROR(P_STEP    => V_STEP,
                      P_CONTEXT => 'CREATE_INITIAL_RFQ | RFQ_ID=' || P_RFQ_ID || ' | PACKAGE=' || P_PACKAGE_ID,
                      P_STATUS  => P_STATUS,
                      P_MESSAGE => P_MESSAGE);
   END CREATE_INITIAL_RFQ;

   -- ============================================
   -- 2. Convert POT customer to actual customer
   -- ============================================
   PROCEDURE CONVERT_POTENTIAL_CUSTOMER
   (
      P_POT_CUST_SITE_ID IN VARCHAR2
     , -- ممكن يكون POT_CUSTOMER_ID أو CUST_SITE_ID
      P_CUSTOMER_ID      OUT NUMBER
     ,P_CUST_SITE_ID     OUT NUMBER
     ,P_STATUS           OUT VARCHAR2
     ,P_MESSAGE          OUT VARCHAR2
   ) AS
      V_MOBILE               VARCHAR2(500);
      V_NAME                 VARCHAR2(500);
      V_ADDRESS              VARCHAR2(500);
      V_POT                  VARCHAR2(50);
      V_STEP                 VARCHAR2(500);
      V_ORIGINAL_CUSTOMER_ID NUMBER;
   BEGIN
      V_STEP := 'Get Customer Info';

      -- Validate input
      IF P_POT_CUST_SITE_ID IS NULL THEN
         P_STATUS  := C_ERROR;
         P_MESSAGE := 'معرف العميل مطلوب';
         RETURN;
      END IF;

      -- Get customer information
      BEGIN
         SELECT POT_CUST, MOBILE_NO, CUST_SITE_NAME, FULL_ADDRESS, CUSTOMER_ID
           INTO V_POT, V_MOBILE, V_NAME, V_ADDRESS, V_ORIGINAL_CUSTOMER_ID
           FROM (
                 -- Existing customers
                 SELECT TO_CHAR(SIT.CUST_SITE_ID) AS CUST_SITE_ID
                        ,'CUST' AS POT_CUST
                        ,SIT.MOBILE AS MOBILE_NO
                        ,SIT.INDV_F_NAME || ' ' || SIT.INDV_M_NAME || ' ' || SIT.INDV_G_NAME || ' ' || SIT.INDV_L_NAME AS CUST_SITE_NAME
                        ,SC.FULL_ADDRESS
                        ,SIT.CUSTOMER_ID
                   FROM AR_CUSTOMER_SITE SIT
                   JOIN AR_CUSTOMER C ON C.CUSTOMER_ID = SIT.CUSTOMER_ID
                   LEFT JOIN AR_CUSTOMER_SITE SC ON SC.CUST_SITE_ID = SIT.CUST_SITE_ID
                  --                   WHERE C.CUSTOMER_TYPE = 'PERSON'  --hashed by asharif
                 where  (C.CUSTOMER_TYPE like  '%PERSON%' or C.CUSTOMER_TYPE like   '%MEDIATION%') --added by asharif

                 UNION ALL

                 -- Potential customers
                 SELECT TO_CHAR(P.POTENTIAL_CUSTOMER_ID) AS CUST_SITE_ID
                        ,'POT' AS POT_CUST
                        ,P.MOBILE_NO AS MOBILE_NO
                        ,NVL(P.POTENTIAL_NAME_L1, P.POTENTIAL_NAME_L2) AS CUST_SITE_NAME
                        ,P.FULL_ADDRESS
                        ,NULL AS CUSTOMER_ID
                   FROM AR_POTENTIAL_CUSTOMER P
                  WHERE P.SECTION_TYPE = 'PERSON'
                    AND P.CUST_SITE_ID IS NULL)
          WHERE CUST_SITE_ID = P_POT_CUST_SITE_ID;
      EXCEPTION
         WHEN NO_DATA_FOUND THEN
            P_STATUS  := C_ERROR;
            P_MESSAGE := 'العميل غير موجود: ' || P_POT_CUST_SITE_ID;
            RETURN;
      END;

      V_STEP := 'Check Customer Type';

      -- If already a real customer, return existing data
      IF V_POT = 'CUST' THEN
         P_CUSTOMER_ID  := V_ORIGINAL_CUSTOMER_ID;
         P_CUST_SITE_ID := TO_NUMBER(P_POT_CUST_SITE_ID);
         P_STATUS       := C_SUCCESS;
         P_MESSAGE      := 'عميل فعلي موجود مسبقاً';

         LOG_ERROR('Customer Already Exists: CUST_ID=' || P_CUSTOMER_ID || ' | SITE_ID=' || P_CUST_SITE_ID);

         RETURN;
      END IF;

      V_STEP := 'Validate Mobile Number';

      IF NVL(TRIM(V_MOBILE), '') = '' THEN
         P_STATUS  := C_ERROR;
         P_MESSAGE := 'لا يوجد رقم جوال للعميل المحتمل رقم: ' || P_POT_CUST_SITE_ID;
         RETURN;
      END IF;

      V_STEP := 'Create ar_customer';

      INSERT INTO AR_CUSTOMER
         (CUSTOMER_ID
         ,CUSTOMER_SYMBOL
         ,CUSTOMER_NAME_L1
         ,CUSTOMER_NAME_L2
         ,INTEREST_TYPE
         ,CUSTOMER_TYPE
         ,FULL_ADDRESS
         ,MOBILE
         ,EMAIL)
      VALUES
         (DML_PKG.GET_NEXT_VALUE('CUSTOMER_ID', 'AR_CUSTOMER')
         ,SM_SYMBOL_PKG.GET_NEXTVAL('AR_INDV_CUSTOMER', V('SESSION_OP_UNIT_ID'), 'SOB')
         ,V_NAME
         ,V_NAME
         ,'NONE'
         ,'PERSON'
         ,V_ADDRESS
         ,V_MOBILE
         ,NULL)
      RETURNING CUSTOMER_ID INTO P_CUSTOMER_ID;

      V_STEP := 'Create ar_customer_site';

      INSERT INTO AR_CUSTOMER_SITE
         (CUST_SITE_ID
         ,INDV_F_NAME
         ,INDV_M_NAME
         ,INDV_G_NAME
         ,INDV_L_NAME
         ,CUSTOMER_ID
         ,FULL_ADDRESS
         ,MOBILE
         ,EMAIL
         ,INDV_ID_NUMBER
         ,SITE_COUNTRY
         ,SITE_CITY
         ,INTEREST_TYPE)
      VALUES
         (DML_PKG.GET_NEXT_VALUE('CUST_SITE_ID', 'AR_CUSTOMER_SITE')
         ,V_NAME
         ,NULL
         ,NULL
         ,V_NAME
         ,P_CUSTOMER_ID
         ,V_ADDRESS
         ,V_MOBILE
         ,NULL
         ,NULL
         ,NULL
         ,NULL
         ,'NONE')
      RETURNING CUST_SITE_ID INTO P_CUST_SITE_ID;

      V_STEP := 'Call convert_pot_to_customer';

      AR_POTENTIAL_CUSTOMER_PKG.CONVERT_POT_TO_CUSTOMER(P_POT_CUST_ID  => P_POT_CUST_SITE_ID,
                                                        P_CUSTOMER_ID  => P_CUSTOMER_ID,
                                                        P_CUST_SITE_ID => P_CUST_SITE_ID,
                                                        P_SECTION_TYPE => 'PERSON');

      V_STEP := 'Update ABSH_CUSTOMER_ADDRESSES';

      UPDATE ABSH_CUSTOMER_ADDRESSES
         SET CUSTOMER_ID = P_CUSTOMER_ID
            ,UPDATED_AT  = SYSTIMESTAMP
       WHERE POT_CUSTOMER_ID = P_POT_CUST_SITE_ID;

      P_STATUS  := C_SUCCESS;
      P_MESSAGE := 'تم تحويل العميل المحتمل إلى عميل فعلي بنجاح';

      LOG_ERROR('POT Converted Successfully: POT_ID=' || P_POT_CUST_SITE_ID || ' → CUST_ID=' || P_CUSTOMER_ID ||
                ' | SITE_ID=' || P_CUST_SITE_ID);

   EXCEPTION
      WHEN OTHERS THEN
         ROLLBACK;
         HANDLE_ERROR(P_STEP    => V_STEP,
                      P_CONTEXT => 'CONVERT_POTENTIAL_CUSTOMER | POT_ID=' || P_POT_CUST_SITE_ID,
                      P_STATUS  => P_STATUS,
                      P_MESSAGE => P_MESSAGE);
   END CONVERT_POTENTIAL_CUSTOMER;

   -- ============================================
   -- 3.Create visit schedule
   -- ============================================
   PROCEDURE CREATE_VISIT_SCHEDULES
   (
      P_RFQ_ID           IN NUMBER
     ,P_VISIT_JSON       IN CLOB
     ,P_COMBINATION_CODE IN VARCHAR2
     ,P_ADDRESS_ID       IN NUMBER
     ,P_PACKAGE_ID       IN NUMBER
     ,P_STATUS           OUT VARCHAR2
     ,P_MESSAGE          OUT VARCHAR2
   ) AS
      V_COUNT_EMP         NUMBER;
      V_SHIFT_ID          VARCHAR2(500);
      V_SERVICE_AREA_ID   NUMBER;
      V_ONE_SCHED_ID      NUMBER;
      V_USED_STAFF_IDS    VARCHAR2(4000);
      V_STAFF_ID          NUMBER;
      V_RES               VARCHAR2(500);
      V_STEP              VARCHAR2(500);
      V_SCHEDULES_CREATED NUMBER := 0;
      V_SCHEDULES_FAILED  NUMBER := 0;
      V_ERROR             VARCHAR2(500);
      V_VALUE             VARCHAR2(500);
   BEGIN
      -- Input Validation
      V_STEP := 'Input Validation';

      IF P_RFQ_ID IS NULL THEN
         P_STATUS  := C_ERROR;
         P_MESSAGE := 'معرف الطلب مطلوب';
         RETURN;
      END IF;

      IF P_VISIT_JSON IS NULL THEN
         P_STATUS  := C_ERROR;
         P_MESSAGE := 'بيانات الزيارات مطلوبة';
         RETURN;
      END IF;

      -- Get Employee Count from combination code
      V_STEP := 'Get Employee Count';

    --   BEGIN -------------------------------------------> dev omar 18-02-2026
    --     SELECT TO_NUMBER(JT.OPTION_DTL_NAME)
    --       INTO V_COUNT_EMP
    --       FROM ABSH_MAIN_PACKAGE_PRICING_OPTIONS P
    --       JOIN JSON_TABLE(P.JSON_DATA, '$.options[*]'
    --            COLUMNS(
    --              OPTION_NAME     VARCHAR2(200) PATH '$.OPTION_Name',
    --              OPTION_DTL_NAME VARCHAR2(200) PATH '$.OPTION_DTL_Name'
    --            )) JT ON 1 = 1
    --      WHERE JT.OPTION_NAME = 'عدد العاملات'
    --        AND P.INDV_SAL_QUOT_ID = P_PACKAGE_ID
    --        AND P.COMBINATION_CODE = P_COMBINATION_CODE;
    --   EXCEPTION
    --      WHEN NO_DATA_FOUND THEN
    --         P_STATUS  := C_ERROR;
    --         P_MESSAGE := 'لم يتم العثور على تفاصيل الخيارات للباقة';
    --         RETURN;
    --   END;
        V_VALUE := ABSH_INDV_QUOT_OPTIONS_PKG.GET_OPTION_VALUE(
                      P_PACKAGE_ID,
                      P_COMBINATION_CODE,
                      ABSH_CREATE_ORDER.C_WORKERS_COUNT
                   );

        IF V_VALUE IS NULL THEN
           P_STATUS  := C_ERROR;
           P_MESSAGE := 'لم يتم العثور على تفاصيل الخيارات للباقة';
           RETURN;
        END IF;

        V_COUNT_EMP := TO_NUMBER(V_VALUE);


      V_STEP := 'Get Service Area';

      BEGIN
         SELECT SERVICE_AREA_ID INTO V_SERVICE_AREA_ID FROM ABSH_CUSTOMER_ADDRESSES WHERE ADDRESS_ID = P_ADDRESS_ID;
      EXCEPTION
         WHEN OTHERS THEN
            V_SERVICE_AREA_ID := NULL;
      END;

      V_STEP := 'Process Visits';

      FOR REC IN (SELECT JT.VISIT_DAY
                        ,JT.VISIT_DATE AS VISIT_DATE
                        ,CASE
                            WHEN REGEXP_LIKE(JT.START_TIME, 'AM|PM', 'i') THEN
                             TO_CHAR(TO_DATE(JT.START_TIME, 'HH:MI AM'), 'HH24:MI')
                            ELSE
                             TO_CHAR(TO_DATE(JT.START_TIME, 'HH24:MI'), 'HH24:MI')
                         END AS START_TIME
                        ,CASE
                            WHEN REGEXP_LIKE(JT.END_TIME, 'AM|PM', 'i') THEN
                             TO_CHAR(TO_DATE(JT.END_TIME, 'HH:MI AM'), 'HH24:MI')
                            ELSE
                             TO_CHAR(TO_DATE(JT.END_TIME, 'HH24:MI'), 'HH24:MI')
                         END AS END_TIME
                        ,(CASE
                            WHEN REGEXP_LIKE(JT.END_TIME, 'AM|PM', 'i') THEN
                             TO_DATE(JT.END_TIME, 'HH:MI AM')
                            ELSE
                             TO_DATE(JT.END_TIME, 'HH24:MI')
                         END - CASE
                            WHEN REGEXP_LIKE(JT.START_TIME, 'AM|PM', 'i') THEN
                             TO_DATE(JT.START_TIME, 'HH:MI AM')
                            ELSE
                             TO_DATE(JT.START_TIME, 'HH24:MI')
                         END) * 24 AS DURATION
                    FROM JSON_TABLE(P_VISIT_JSON,
                                    '$[*]' COLUMNS(VISIT_DAY VARCHAR2(50) PATH '$.day_en',
                                            VISIT_DATE VARCHAR2(20) PATH '$.date',
                                            START_TIME VARCHAR2(20) PATH '$.startTime',
                                            END_TIME VARCHAR2(20) PATH '$.endTime')) JT) LOOP
         BEGIN
            IF REC.VISIT_DATE IS NULL THEN
               RAISE_APPLICATION_ERROR(-20001, 'تاريخ الزيارة فارغ');
            END IF;

            BEGIN
            --    IF REGEXP_SUBSTR(P_COMBINATION_CODE, '[^-]+', 1, 1) = '99' THEN
            --       V_SHIFT_ID := REGEXP_SUBSTR(P_COMBINATION_CODE, '[^-]+', 1, 2);
            --    ELSE
            --       V_SHIFT_ID := NULL;
            --    END IF;
            V_SHIFT_ID := ABSH_INDV_QUOT_OPTIONS_PKG.GET_OPTION_DTL_ID(
                 P_PACKAGE_ID,
                 P_COMBINATION_CODE,
                 ABSH_CREATE_ORDER.C_SHIFTS
              );
            EXCEPTION
               WHEN NO_DATA_FOUND THEN
                  V_SHIFT_ID := NULL;
            END;

            INSERT INTO ABSH_VISIT_SCHEDULE
               (INDV_RFQ_ID
               ,ADDRESS_ID
               ,INDV_SAL_QUOT_ID
               ,VISIT_DAY
               ,VISIT_DATE
               ,START_TIME
               ,END_TIME
               ,VISIT_DURATION_HR
               ,CREATED_AT
               ,SHIFT_ID
               ,TOTAL_WORKERS)
            VALUES
               (P_RFQ_ID
               ,P_ADDRESS_ID
               ,P_PACKAGE_ID
               ,REC.VISIT_DAY
               ,REC.VISIT_DATE
               ,REC.START_TIME
               ,REC.END_TIME
               ,REC.DURATION
               ,SYSTIMESTAMP
               ,V_SHIFT_ID
               ,V_COUNT_EMP)
            RETURNING SCHEDULE_ID INTO V_ONE_SCHED_ID;

            V_USED_STAFF_IDS := '';

            FOR C IN 1 .. V_COUNT_EMP LOOP
               V_RES := ABSH_CREATE_ORDER.ASSIGN_STAFF(P_INDV_RFQ_ID     => P_RFQ_ID,
                                                       P_ONE_SCHED_ID    => V_ONE_SCHED_ID,
                                                       P_SERVICE_AREA_ID => V_SERVICE_AREA_ID,
                                                       P_USED_STAFF_IDS  => V_USED_STAFF_IDS);

               IF V_RES LIKE 'OK|%' THEN
                  BEGIN
                     V_STAFF_ID := TO_NUMBER(SUBSTR(V_RES, INSTR(V_RES, '=') + 1));

                     IF V_USED_STAFF_IDS IS NULL OR V_USED_STAFF_IDS = '' THEN
                        V_USED_STAFF_IDS := V_STAFF_ID;
                     ELSE
                        V_USED_STAFF_IDS := V_USED_STAFF_IDS || ',' || V_STAFF_ID;
                     END IF;
                  EXCEPTION
                     WHEN OTHERS THEN
                        LOG_ERROR('[WARN] Failed to extract staff_id from: ' || V_RES);
                  END;
               END IF;
            END LOOP;

            V_SCHEDULES_CREATED := V_SCHEDULES_CREATED + 1;

            LOG_ERROR('Schedule Created: ID=' || V_ONE_SCHED_ID || ' for RFQ=' || P_RFQ_ID || ' | DATE=' ||
                      REC.VISIT_DATE || ' | Staff: ' || NVL(V_USED_STAFF_IDS, 'NONE'));

         EXCEPTION
            WHEN OTHERS THEN
               V_SCHEDULES_FAILED := V_SCHEDULES_FAILED + 1;

               LOG_ERROR('Schedule Error for date ' || REC.VISIT_DATE || ' | STEP: ' || V_STEP || ' | ERROR: ' ||
                         SUBSTR(SQLERRM, 1, 500));

               RAISE;
         END;
      END LOOP;

      V_STEP := 'Finalize';

      IF V_SCHEDULES_CREATED = 0 THEN
         P_STATUS  := C_ERROR;
         P_MESSAGE := 'فشل إنشاء كل الجداول';
      ELSIF V_SCHEDULES_FAILED > 0 THEN
         P_STATUS  := C_PARTIAL;
         P_MESSAGE := 'تم إنشاء ' || V_SCHEDULES_CREATED || ' جدولة، فشل ' || V_SCHEDULES_FAILED;
      ELSE
         P_STATUS  := C_SUCCESS;
         P_MESSAGE := 'تم إنشاء ' || V_SCHEDULES_CREATED || ' جدولة بنجاح';
      END IF;

   EXCEPTION
      WHEN OTHERS THEN
         HANDLE_ERROR(P_STEP    => V_STEP,
                      P_CONTEXT => 'CREATE_VISIT_SCHEDULES | RFQ=' || P_RFQ_ID || ' | Created=' || V_SCHEDULES_CREATED ||
                                   ' | Failed=' || V_SCHEDULES_FAILED,
                      P_STATUS  => P_STATUS,
                      P_MESSAGE => P_MESSAGE);
   END CREATE_VISIT_SCHEDULES;

   -- ============================================
   -- 4. Complete contract once payment is made
   -- ============================================
   PROCEDURE COMPLETE_CONTRACT_AFTER_PAYMENT
   (
      P_RFQ_ID            IN NUMBER
     ,P_PAYMENT_STATUS    IN VARCHAR2
     ,P_PAYMENT_REFERENCE IN VARCHAR2 DEFAULT NULL
     ,P_CONTRACT_SYMBOL   OUT VARCHAR2
     ,P_STATUS            OUT VARCHAR2
     ,P_MESSAGE           OUT VARCHAR2
   ) AS
      V_CUST_SITE_ID     VARCHAR2(100);
      V_CUSTOMER_ID      NUMBER;
      V_NEW_CUSTOMER_ID  NUMBER;
      V_NEW_CUST_SITE_ID NUMBER;
      V_PACKAGE_ID       NUMBER;
      V_COMBINATION_CODE VARCHAR2(500);
      V_VISIT_JSON       CLOB;
      V_ADDRESS_ID       NUMBER;
      V_RESULT_CONTRACT  VARCHAR2(3000);
      V_STEP             VARCHAR2(500);
      V_CONVERT_STATUS   VARCHAR2(50);
      V_CONVERT_MSG      VARCHAR2(500);
      V_SCHEDULE_STATUS  VARCHAR2(50);
      V_SCHEDULE_MSG     VARCHAR2(500);
      V_DATA_FOUND       BOOLEAN := FALSE;
      L_SQLERRM          VARCHAR2(500);

   BEGIN
    --   SAVEPOINT SP_PAYMENT_START;
    --   L_SQLERRM := SQLERRM;

      V_STEP := 'Input Validation';
      IF P_RFQ_ID IS NULL THEN
         P_STATUS  := C_ERROR;
         P_MESSAGE := 'معرف الطلب مطلوب';
         RETURN;
      END IF;

      V_STEP := 'Validate Payment';

      IF NVL(P_PAYMENT_STATUS, C_FAILED) != C_SUCCESS THEN
         UPDATE INDV_SAL_RFQ SET RFQ_STATUS = C_STATUS_CANCELLED WHERE INDV_RFQ_ID = P_RFQ_ID;

         P_STATUS  := C_PAYMENT_FAILED;
         P_MESSAGE := 'فشلت عملية الدفع. طلبك محفوظ رقم: ' || P_RFQ_ID;

         LOG_ERROR('Payment Failed for RFQ: ' || P_RFQ_ID || ' | REF: ' || NVL(P_PAYMENT_REFERENCE, 'N/A') ||
                   ' | STATUS: ' || P_PAYMENT_STATUS);

         RETURN;
      END IF;

      V_STEP := 'Get RFQ Data';

      FOR REC IN (SELECT R.CUST_SITE_ID
                        ,R.CUSTOMER_ID
                        ,R.INDV_SAL_QUOT_ID
                        ,D.COMBINATION_CODE
                        ,D.SCHEDULE_JSON
                        ,D.ADDRESS_ID
                    FROM INDV_SAL_RFQ R
                    JOIN ABSH_DTL_INDV_SAL_RFQ D ON D.INDV_RFQ_ID = R.INDV_RFQ_ID
                   WHERE R.INDV_RFQ_ID = P_RFQ_ID) LOOP
         V_CUST_SITE_ID     := REC.CUST_SITE_ID;
         V_CUSTOMER_ID      := REC.CUSTOMER_ID;
         V_PACKAGE_ID       := REC.INDV_SAL_QUOT_ID;
         V_COMBINATION_CODE := REC.COMBINATION_CODE;
         V_VISIT_JSON       := REC.SCHEDULE_JSON;
         V_ADDRESS_ID       := REC.ADDRESS_ID;
         V_DATA_FOUND       := TRUE;
      END LOOP;

      IF NOT V_DATA_FOUND THEN
         RAISE_APPLICATION_ERROR(-20001,
                                 'لم يتم العثور على بيانات الطلب رقم: ' || P_RFQ_ID);
      END IF;

      V_STEP := 'Convert Customer if Needed';

      CONVERT_POTENTIAL_CUSTOMER(P_POT_CUST_SITE_ID => V_CUST_SITE_ID,
                                 P_CUSTOMER_ID      => V_NEW_CUSTOMER_ID,
                                 P_CUST_SITE_ID     => V_NEW_CUST_SITE_ID,
                                 P_STATUS           => V_CONVERT_STATUS,
                                 P_MESSAGE          => V_CONVERT_MSG);

      IF V_CONVERT_STATUS = C_ERROR THEN
         RAISE_APPLICATION_ERROR(-20002, 'خطأ في تحويل العميل: ' || V_CONVERT_MSG);
      END IF;

      V_STEP := 'Update RFQ with New Customer';

      IF V_NEW_CUSTOMER_ID IS NOT NULL THEN
         UPDATE INDV_SAL_RFQ
            SET CUSTOMER_ID  = V_NEW_CUSTOMER_ID
               ,CUST_SITE_ID = V_NEW_CUST_SITE_ID
          WHERE INDV_RFQ_ID = P_RFQ_ID;
      END IF;

      V_STEP            := 'Create Contract';
      V_RESULT_CONTRACT := INDIVIDUAL_SAL_CONTRACT_PKG.CREATE_CONTRACT2(P_INDV_RFQ_ID           => P_RFQ_ID,
                                                                        P_CONTRACT_SYMBOL       => P_CONTRACT_SYMBOL,
                                                                        P_CREATED_WITH_SADAD    => 'YES',
                                                                        P_CREATE_WITH_SADAD_INS => 'YES',
                                                                        P_CREATE_WITH_SADAD_DEP => 'YES');

      V_STEP := 'Create Schedules';

      CREATE_VISIT_SCHEDULES(P_RFQ_ID           => P_RFQ_ID,
                             P_VISIT_JSON       => V_VISIT_JSON,
                             P_COMBINATION_CODE => V_COMBINATION_CODE,
                             P_ADDRESS_ID       => V_ADDRESS_ID,
                             P_PACKAGE_ID       => V_PACKAGE_ID,
                             P_STATUS           => V_SCHEDULE_STATUS,
                             P_MESSAGE          => V_SCHEDULE_MSG);

      IF V_SCHEDULE_STATUS = C_ERROR THEN
         RAISE_APPLICATION_ERROR(-20003, 'خطأ في إنشاء الجدولة: ' || V_SCHEDULE_MSG);
      END IF;

      V_STEP := 'Finalize Contract';

      P_STATUS  := C_SUCCESS;
      P_MESSAGE := 'تم إنشاء العقد رقم ' || P_CONTRACT_SYMBOL || ' بنجاح';

      LOG_ERROR('Contract Completed Successfully: ' || P_CONTRACT_SYMBOL || ' for RFQ=' || P_RFQ_ID);

   EXCEPTION
      WHEN OTHERS THEN
        --  ROLLBACK TO SP_PAYMENT_START;
         L_SQLERRM := SQLERRM;
         V_STEP := NVL(V_STEP, 'Unknown Step');

         UPDATE INDV_SAL_RFQ
            SET RFQ_STATUS = C_STATUS_CANCELLED --'PAID_ERROR'
         -- ERROR_MESSAGE = 'STEP: ' || v_step || ' - ' || SUBSTR(l_SQLERRM, 1, 500)
          WHERE INDV_RFQ_ID = P_RFQ_ID;

         P_STATUS  := C_ERROR;
         P_MESSAGE := 'خطأ في المرحلة: ' || V_STEP || ' - ' || SUBSTR(L_SQLERRM, 1, 200);

         HANDLE_ERROR(P_STEP    => NVL(V_STEP, 'Unknown Step'),
                      P_CONTEXT => 'COMPLETE_CONTRACT Error | ' || 'RFQ=' || P_RFQ_ID || ' | ' || 'ERROR=' ||
                                   SUBSTR(L_SQLERRM, 1, 500) || ' | ' || 'BACKTRACE=' ||
                                   SUBSTR(DBMS_UTILITY.FORMAT_ERROR_BACKTRACE, 1, 500),
                      P_STATUS  => P_STATUS,
                      P_MESSAGE => P_MESSAGE);

   END COMPLETE_CONTRACT_AFTER_PAYMENT;
   -----------------------------------------------------------------------------------------
    PROCEDURE UPDATE_ACCOUNT_AND_COMMENT(
        P_CUST_CONTRACT_ID    NUMBER,
        P_SDAD_ACCOUNT_NUMBER VARCHAR2,
        P_NEW_PROCESS_STATUS  VARCHAR2,
        P_WORKFLOW_ID         NUMBER
    )
    IS
    BEGIN
        UPDATE REC_CUST_CONTRACT
        SET SDAD_ACCOUNT_NUMBER   = P_SDAD_ACCOUNT_NUMBER,
            WORKFLOW_ID           = P_WORKFLOW_ID,
            SDAD_LAST_UPDATE_DATE = SYSDATE,
            SDAD_UPLOAD_STATUS    = P_NEW_PROCESS_STATUS
        WHERE CUST_CONTRACT_ID = P_CUST_CONTRACT_ID;
    EXCEPTION
        WHEN OTHERS THEN
            RAISE;
    END UPDATE_ACCOUNT_AND_COMMENT;


    PROCEDURE LOG_SDAD_RECEIPTS_JSON (
        P_EXECUTION_ID     IN VARCHAR2,
        P_BILL_CYCLE       IN VARCHAR2,
        P_CUST_CONTRACT_ID IN NUMBER
    ) AS
        PRAGMA AUTONOMOUS_TRANSACTION;
        V_JSON   CLOB;
        V_COUNT  NUMBER := 0;
    BEGIN
        SELECT JSON_ARRAYAGG(
                   JSON_OBJECT(
                       'RECEIPT_ID'             VALUE R.RECEIPT_ID,
                       'RECEIPT_DATE'           VALUE TO_CHAR(R.RECEIPT_DATE, 'YYYY-MM-DD HH24:MI:SS'),
                       'TOT_AMOUNT'             VALUE R.TOT_AMOUNT,
                       'NET_AMOUNT'             VALUE R.NET_AMOUNT,
                       'TAX_AMOUNT'             VALUE R.TAX_AMOUNT,
                       'REMAIN_AMOUNT'          VALUE R.REMAIN_AMOUNT,
                       'CONFIRMED'              VALUE R.CONFIRMED,
                       'CONFIRM_DATE'           VALUE TO_CHAR(R.CONFIRM_DATE, 'YYYY-MM-DD HH24:MI:SS'),
                       'CONFIRM_USER_ID'        VALUE R.CONFIRM_USER_ID,
                       'CONFIRMED_BY_NAME'      VALUE R.CONFIRMED_BY_NAME,
                       'COMPLETED'              VALUE R.COMPLETED,
                       'COMPLETE_STATUS'        VALUE R.COMPLETE_STATUS,
                       'BANK_CONF_STATUS'       VALUE R.BANK_CONF_STATUS,
                       'BANK_CONF_DATE'         VALUE TO_CHAR(R.BANK_CONF_DATE, 'YYYY-MM-DD HH24:MI:SS'),
                       'BANK_CONF_USER_ID'      VALUE R.BANK_CONF_USER_ID,
                       'BANK_CONFIRMED_BY_NAME' VALUE R.BANK_CONFIRMED_BY_NAME,
                       'PAY_METHOD_BANK_ID'     VALUE R.PAY_METHOD_BANK_ID,
                       'PAY_METHOD_NAME'        VALUE R.PAY_METHOD_NAME,
                       'PAYMENT_METHOD_TYPE'    VALUE R.PAYMENT_METHOD_TYPE,
                       'BANK_NAME'              VALUE R.BANK_NAME,
                       'BANK_ACCOUNT_NUMBER'    VALUE R.BANK_ACCOUNT_NUMBER,
                       'PAY_METHOD_IDENTIFIER'  VALUE AR_PAYMENT_METHOD_PKG.GET_PAY_METHOD_IDENTIFIER(R.PAY_METHOD_BANK_ID),
                       'SADAD_PAYMENT_ID'       VALUE R.SADAD_PAYMENT_ID,
                       'SADAD_BILL_CYCLE'       VALUE R.SADAD_BILL_CYCLE,
                       'SADAD_ACCOUNT_NUMBER'   VALUE R.SADAD_ACCOUNT_NUMBER,
                       'OLD_RECEIPT_ID'         VALUE R.OLD_RECEIPT_ID,
                       'CREATION_DATE'          VALUE TO_CHAR(R.CREATION_DATE, 'YYYY-MM-DD HH24:MI:SS'),
                       'CREATED_BY_NAME'        VALUE R.CREATED_BY_NAME,
                       'ATTACHMENT_URL'         VALUE R.ATTACHMENT_URL,
                       'DEPOSIT_RECEIPT'        VALUE RBP.DEPOSIT_RECEIPT,
                       'DISTRIBUTED_AMOUNT'     VALUE RBP.RECEIPT_AMOUNT,
                       'PAYMENT_STATUS'         VALUE
                           CASE
                               WHEN R.CONFIRMED = 1 AND R.CONFIRM_DATE IS NOT NULL AND R.COMPLETED = 1
                                   THEN 'PAID_AND_CONFIRMED'
                               WHEN R.CONFIRMED = 1 AND R.COMPLETED = 0
                                   THEN 'CONFIRMED_NOT_COMPLETED'
                               WHEN R.CONFIRMED = 0
                                   THEN 'NOT_CONFIRMED'
                               ELSE 'UNKNOWN'
                           END
                       RETURNING CLOB
                   )
                   RETURNING CLOB
               ),
               COUNT(*)
        INTO   V_JSON, V_COUNT
        FROM   AR_RECEIPT R, AR_RECEIPT_BUSINESS_PARTNER RBP
        WHERE  R.RECEIPT_ID       = RBP.RECEIPT_ID
        AND    R.SADAD_PAYMENT_ID IS NULL
        AND    RBP.CUST_CONTRACT_ID = P_CUST_CONTRACT_ID;

        INSERT INTO AR_SDAD_PROC_DEBUG_LOG (
            EXECUTION_ID, PROC_NAME, BILL_CYCLE, STEP_NUMBER, STEP_NAME,
            STEP_DETAILS, VAR_NAME, VAR_VALUE,
            SESSION_USER_ID, ERROR_FLAG
        ) VALUES (
            P_EXECUTION_ID, 'UPDATE_BILL_SUCCESS', P_BILL_CYCLE, 4,
            'RECEIPTS_SNAPSHOT',
            V_JSON,
            'RECEIPTS_COUNT',
            TO_CHAR(V_COUNT),
            NVL(TO_NUMBER(V('SESSION_USER_ID')), -1),
            'N'
        );
        COMMIT;
    EXCEPTION
        WHEN OTHERS THEN
            ROLLBACK;
            DECLARE
                V_SQLERRM VARCHAR2(500) := SQLERRM;
            BEGIN
                INSERT INTO AR_SDAD_PROC_DEBUG_LOG (
                    EXECUTION_ID, PROC_NAME, BILL_CYCLE, STEP_NUMBER, STEP_NAME,
                    STEP_DETAILS, ERROR_FLAG
                ) VALUES (
                    P_EXECUTION_ID, 'UPDATE_BILL_SUCCESS', P_BILL_CYCLE, 4,

                    'RECEIPTS_SNAPSHOT_ERROR',
                    V_SQLERRM,
                    'Y'
                );
                COMMIT;
            EXCEPTION
                WHEN OTHERS THEN NULL;
            END;
    END LOG_SDAD_RECEIPTS_JSON;

    -- ====================================================================

    PROCEDURE UPDATE_BILL_SUCCESS(
        P_BILL_CYCLE     IN VARCHAR2,
        P_INVOICE_AMOUNT IN NUMBER,
        P_WF_ID IN NUMBER DEFAULT NULL,
        p_CUST_CONTRACT_IDS IN VARCHAR2 DEFAULT NULL
    ) AS
        V_VALID             VARCHAR2(100);
        V_BILL_TYPE         VARCHAR2(100);
        V_ACCOUNT_NUMBER    VARCHAR2(100);
        V_CUST_CONTRACT_ID  NUMBER;
        V_WORKFLOW_ID       NUMBER;
        V_CUSTOMER_SITE_ID  NUMBER;
        V_MOBILE            VARCHAR2(100);
        V_CUSTOMER_F_NAME   VARCHAR2(1000);
        V_CONTRACT_SYMBOL   VARCHAR2(100);
        V_LAST_INVOICE_DATE DATE;
        V_MSG               VARCHAR2(100);
        L_SENDER_DETAILS    VARCHAR2(1000);
        V_DEPOSIT_AMOUNT    NUMBER := 0;
        V_HAS_USAGE         NUMBER := 0;
    BEGIN
        SM_SESSION_PKG.SET_USER_SESSION_ENV(-1, 1001);

        BEGIN  --replace this block by parameter p_account_numbr  from workflow app 146

            SELECT ACCOUNT_NUMBER , JSON_VALUE(JSON_DETAIL,'$.CUST_CONTRACT_ID.value') AS CUST_CONTRACT_ID
            INTO   V_ACCOUNT_NUMBER ,V_CUST_CONTRACT_ID
            FROM   AR_INVOICE_SDAD_BILLS
            WHERE  BILL_CYCLE = P_BILL_CYCLE
            AND    STATUS         = 'NEW';


        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                V_ACCOUNT_NUMBER := NULL;
        END;
          --replace this block by parameter p_CUST_CONTRACT_ID, apex_WORKFLOW_ID  from workflow app 146
        IF V_ACCOUNT_NUMBER IS NOT NULL THEN
            BEGIN
                SELECT  WORKFLOW_ID
                INTO    V_WORKFLOW_ID
                FROM   REC_CUST_CONTRACT
                WHERE  CUST_CONTRACT_ID =V_CUST_CONTRACT_ID;

                -- SELECT CUST_CONTRACT_ID, WORKFLOW_ID
                -- INTO   V_CUST_CONTRACT_ID, V_WORKFLOW_ID
                -- FROM   REC_CUST_CONTRACT
                -- WHERE  CUST_CONTRACT_ID = (
                --            SELECT CUST_CONTRACT_ID
                --            FROM   REC_CUST_CONTRACT
                --            WHERE  SDAD_ACCOUNT_NUMBER = V_ACCOUNT_NUMBER
                --            AND    CUST_CONTRACT_SYMBOL IS NOT NULL
                --        );
            EXCEPTION
                WHEN NO_DATA_FOUND THEN
                    V_CUST_CONTRACT_ID := NULL;
                    V_WORKFLOW_ID      := NULL;
            END;
        END IF;

        IF V_CUST_CONTRACT_ID IS NOT NULL THEN
            BEGIN
                SELECT NVL(SUM(RBP.RECEIPT_AMOUNT), 0)

                INTO   V_DEPOSIT_AMOUNT
                FROM   AR_RECEIPT_BUSINESS_PARTNER RBP,
                       AR_RECEIPT R
                WHERE  RBP.RECEIPT_ID       = R.RECEIPT_ID
                AND    RBP.CUST_CONTRACT_ID = V_CUST_CONTRACT_ID
                AND    RBP.DEPOSIT_RECEIPT  = 'INDV_DEPOSIT'
                AND    R.CONFIRMED          = 1
                AND    R.SADAD_PAYMENT_ID IS NULL;
            EXCEPTION
                WHEN OTHERS THEN
                    V_DEPOSIT_AMOUNT := 0;
            END;

            LOG_SDAD_RECEIPTS_JSON(NULL, P_BILL_CYCLE, V_CUST_CONTRACT_ID);


            BEGIN
                SELECT COUNT(*)
                INTO   V_HAS_USAGE
                FROM   AR_INVOICE
                WHERE  CUST_CONTRACT_ID = V_CUST_CONTRACT_ID
                AND    INVOICE_TYPE = 'INDV_STANDARD'
--                AND    ROWNUM = 1
                ;
--            EXCEPTION
--                WHEN OTHERS THEN
--                    V_HAS_USAGE := 0;
            END;
        END IF;

        IF  ROUND(NVL(V_DEPOSIT_AMOUNT, 0), 0) > 0
            AND ROUND(NVL(P_INVOICE_AMOUNT, 0), 0) > 0
            AND ROUND(NVL(V_DEPOSIT_AMOUNT, 0), 0) >= ROUND(NVL(P_INVOICE_AMOUNT, 0), 0)
            AND V_HAS_USAGE = 0
        THEN
            APEX_SESSION.CREATE_SESSION(146, 1, 'MFARAG');

            SDAD_PORTAL_PKG.INSERT_SDADA_WF_LOG(
                p_WF_ID                  => V_WORKFLOW_ID,
                p_REQUEST_TYPE           => 'BILLS',
                p_ACCOUNT_NUMBER         => V_ACCOUNT_NUMBER,
                p_ACCOUNT_TYPE           => NULL,
                p_ACCOUNT_STATUS         => NULL,
                p_ACCOUNT_PROCESS_STATUS => NULL,
                p_SENT_AMOUNT            => NULL,
                p_AMOUNT                 => P_INVOICE_AMOUNT,
                p_BILL_CYCLE             => P_BILL_CYCLE,
                p_BILL_TYPE              => 'NEW',
                p_BILL_STATUS            => 6,
                p_BILL_PROCESS_STATUS    => 3,
                p_CUST_CONTRACT_ID       => V_CUST_CONTRACT_ID,
                p_STATUS_MSG             => 'Bill Cycle (' || P_BILL_CYCLE
                                            || ') Skipped - Customer Already Paid By Other Method. '
                                            || 'Deposit Amount: ' || V_DEPOSIT_AMOUNT
                                            || ', Invoice Amount: ' || P_INVOICE_AMOUNT
                                            || '. Workflow Terminated For Account ('
                                            || V_ACCOUNT_NUMBER || ')',
                p_MOBILE_NUMBER          => NULL,
                p_SENT_SMS               => NULL,
                p_SMS_MSG                => NULL,
                p_SADAD_RESPONSE         => NULL,
                p_ERROR_MSG              => NULL,
                p_ACTION_DATE            => SYSDATE,
                p_ACTION_USER            => V('SESSION_USER_ID'),
                P_JSON_DETAIL            => NULL
            );

            -- add by omar 12-04-2026
            IF V_WORKFLOW_ID IS NOT NULL THEN
                APEX_WORKFLOW.TERMINATE(p_instance_id => V_WORKFLOW_ID);  -- stop workflow
            END IF;

            -- TODO: Discuss with Eng.Obada how related tables should be handled: BILLS , AR_INVOICE_SDAD_BILLS
            -- CREATE NEW WORK FLOW WITH AMOUNT 0 FOR THIS P_BILL_CYCLE which has already been terminated

            RETURN;
        END IF;

    V_VALID     := SDAD_PKG.UPDATE_SADAD_UPLOAD_STATUS(V_ACCOUNT_NUMBER, SYSDATE);  --ask_mobada

-- hased after ASK ENG MO.OBADA for this update because invoice inserted status new already
--        UPDATE AR_INVOICE_SDAD_BILLS
--        SET STATUS         = 'NEW',
--            INVOICE_AMOUNT = P_INVOICE_AMOUNT,
--            ACTION_DATE    = SYSTIMESTAMP
--        WHERE BILL_CYCLE = P_BILL_CYCLE
--        RETURNING ACCOUNT_NUMBER INTO V_ACCOUNT_NUMBER;

       /* FOR I IN (
            SELECT S.MOBILE,
                   C.CUST_CONTRACT_SYMBOL,
                   C.CUST_CONTRACT_ID,
                   C.CUSTOMER_SITE_ID,
                   S.INDV_F_NAME
            FROM   AR_CUSTOMER_SITE S,
                   REC_CUST_CONTRACT C
            WHERE  C.CUSTOMER_SITE_ID = S.CUST_SITE_ID
            AND    C.CUST_CONTRACT_ID = (
                       SELECT MAX(CUST_CONTRACT_ID)
                       FROM   REC_CUST_CONTRACT
                       WHERE  SDAD_ACCOUNT_NUMBER = V_ACCOUNT_NUMBER
                       AND    CUST_CONTRACT_SYMBOL IS NOT NULL
                   )
        ) LOOP
            V_CONTRACT_SYMBOL  := I.CUST_CONTRACT_SYMBOL;
            V_MOBILE           := I.MOBILE;
            V_CUST_CONTRACT_ID := I.CUST_CONTRACT_ID;
            V_CUSTOMER_SITE_ID := I.CUSTOMER_SITE_ID;
            V_CUSTOMER_F_NAME  := I.INDV_F_NAME;
        END LOOP;

        SELECT JSON_OBJECT(
                   'VIEW_TABLE_NAME'  VALUE 'REC_CUST_CONTRACT',
                   'VIEW_TABLE_PK'    VALUE V_CUST_CONTRACT_ID,
                   'ACCOUNT_NUMBER'   VALUE V_ACCOUNT_NUMBER,
                   'BILL_CYCLE'       VALUE P_BILL_CYCLE,
                   'REQ_NUMBER'       VALUE P_BILL_CYCLE,
                   'REQ_TYPE'         VALUE 'NEW_BILL',
                   'SADAD_PAYMENT_ID' VALUE NULL FORMAT JSON
               )
        INTO   L_SENDER_DETAILS
        FROM   DUAL;


        V_BILL_TYPE := SDAD_PKG.GET_SDAD_BILL_DETAILS_TYPE(P_BILL_CYCLE);

        IF V_MOBILE IS NOT NULL THEN
            IF SDAD_PKG.IS_MESSGAE_SENT_BEFORE(
                   P_REQ_TYPE   => 'NEW_BILL',
                   P_REQ_NUMBER => P_BILL_CYCLE
               ) = 'NO'
            THEN
                IF V_BILL_TYPE = 'NORMAL'
                   AND ROUND(NVL(P_INVOICE_AMOUNT, 0), 2) > 0
                THEN
                    BEGIN
                        SELECT MAX(TO_DESERVE_DATE)
                        INTO   V_LAST_INVOICE_DATE
                        FROM   AR_INVOICE
                        WHERE  CUST_CONTRACT_ID = V_CUST_CONTRACT_ID
                        AND    INVOICE_TYPE = 'INDV_STANDARD';
                    EXCEPTION
                        WHEN NO_DATA_FOUND THEN
                            V_LAST_INVOICE_DATE := NULL;
                    END;

                    V_MSG := SM_SMS_PKG.SEND_SMS2(
                        P_TO => V_MOBILE,
                        P_MESSAGE => HR_NOTIFICATION_PKG.REPLACE_SMS_TEXT_TEMPLATE(
                            'SDAD_SMS_NEW_BILL',
                            '[P_LAST_INVOICE_DATE]' || TO_CHAR(V_LAST_INVOICE_DATE,'dd/mm/yyyy') || '##' ||
                            '[CUSTOMER_F_NAME]'     || V_CUSTOMER_F_NAME || '##' ||
                            '[CUST_CONTRACT_SYMBOL]'|| V_CONTRACT_SYMBOL || '##' ||
                            '[P_ACCOUNT_NUMBER]'    || V_ACCOUNT_NUMBER || '##' ||
                            '[P_BILL_AMOUNT]'       || ROUND(P_INVOICE_AMOUNT) || '##' ||
                            '[P_DUE_DATE]'          || TO_CHAR(SYSDATE + 28,'dd/mm/yyyy')
                        ),
                        P_USER_ID        => -1,
                        P_SENDER_DETAILS => L_SENDER_DETAILS
                    );

                ELSIF V_BILL_TYPE = 'COLLECTION' THEN

                    V_MSG := SM_SMS_PKG.SEND_SMS2(
                        P_TO => V_MOBILE,
                        P_MESSAGE => HR_NOTIFICATION_PKG.REPLACE_SMS_TEXT_TEMPLATE(
                            'SDAD_SMS_COLLECTION_BILL',
                            '[CUSTOMER_F_NAME]'  || V_CUSTOMER_F_NAME || '##' ||
                            '[P_ACCOUNT_NUMBER]' || V_ACCOUNT_NUMBER || '##' ||
                            '[P_BILL_AMOUNT]'    || ROUND(P_INVOICE_AMOUNT)
                        ),
                        P_USER_ID        => -1,
                        P_SENDER_DETAILS => L_SENDER_DETAILS
                    );
                END IF;

            END IF;
        END IF;*/

    EXCEPTION
        WHEN OTHERS THEN
            APP_ERROR_PKG.INS_SM_DB_ERROR(
                P_FROM_MODULE   => 'CLOUD_SADAD',
                P_FROM_OWNER    => 'RUNERP_CODE',
                P_FROM_OBJECT   => 'UPDATE_BILL_SUCCESS',
                P_OBJECT_TYPE   => 'PROCEDURE',
                P_ERROR_MESSAGE => SQLERRM,
                P_ERROR_STMT    => 'BILL_CYCLE = ' || P_BILL_CYCLE
            );
            RAISE;
    END UPDATE_BILL_SUCCESS;
    -- ====================================================================
    PROCEDURE UPDATE_BILL_FAILED(
        P_BILL_CYCLE IN VARCHAR2,
        P_STATUS     IN VARCHAR2
    ) AS
    BEGIN
        UPDATE AR_INVOICE_SDAD_BILLS
        SET STATUS      = P_STATUS,
            ACTION_DATE = SYSTIMESTAMP
        WHERE BILL_CYCLE = P_BILL_CYCLE;

        COMMIT;
    EXCEPTION
        WHEN OTHERS THEN
            ROLLBACK;
            RAISE;
    END UPDATE_BILL_FAILED;

    -- ====================================================================
    PROCEDURE REFRESH_DWH_AFTER_PAYMENT (
        P_WF_ID            IN NUMBER,
        P_LOG_ID           IN NUMBER,
        P_ACCOUNT_NUMBER   IN VARCHAR2,
        P_AMOUNT           IN NUMBER,
        P_BILL_CYCLE       IN VARCHAR2,
        P_SADAD_PAYMENT_ID IN NUMBER,
        P_REQUEST_TYPE     IN VARCHAR2,
        P_ACTION_DATE      IN DATE,
        P_PAYMENT_KIND     IN VARCHAR2
    ) IS
    BEGIN
        FOR C IN (
            SELECT CUST_CONTRACT_ID
            FROM   REC_CUST_CONTRACT
            WHERE  SDAD_ACCOUNT_NUMBER = P_ACCOUNT_NUMBER
              AND  SECTION_TYPE = 'PERSON'
        ) LOOP
            INDIVIDUAL_SAL_CONTRACT_PKG.UPD_INDIVIDUAL_DWH_REC_CUST_CONTRACT(
                P_CUST_CONTRACT_ID => C.CUST_CONTRACT_ID
            );
        END LOOP;

        UPDATE DWH_DMSTC_SADAD_ACC_BALANCE
        SET DUE_AMOUNT_REMAIN      = (SELECT NVL(SUM(CONTRACT_BAL), 0)
                                      FROM   DWH_REC_CUST_CONTRACT
                                      WHERE  SDAD_ACCOUNT_NUMBER = P_ACCOUNT_NUMBER),
            LAST_BILL_AMOUNT       = (SELECT AMOUNT_DUE FROM BILLS
                                      WHERE  ID = (SELECT MAX(ID) FROM BILLS
                                                   WHERE BILLING_ACCOUNT = P_ACCOUNT_NUMBER)),
            LAST_BILL_PAYED_AMOUNT = P_AMOUNT,
            BILL_CYCLE             = P_BILL_CYCLE,
            PAYMENT_DATE           = P_ACTION_DATE,
            PAY_REQ_ID             = P_SADAD_PAYMENT_ID,
            PAY_REQ_TYPE           = P_REQUEST_TYPE,
            LAST_REFRESH_DATE      = SYSTIMESTAMP,
            REFRESH_STATUS         = 'UPDATED'
        WHERE SDAD_ACCOUNT_NUMBER  = P_ACCOUNT_NUMBER;
    END REFRESH_DWH_AFTER_PAYMENT;

    -- ====================================================================
    -- FUNCTION PROCESS_BILL_PAYMENT(P_WF_ID NUMBER) RETURN VARCHAR2 IS
    --     V_DUPLICATE_CHECK    NUMBER := 0;
    --     V_UNPAID_BILLS_COUNT NUMBER := 0;
    --     V_PAYMENT_REMAIN     NUMBER := 0;
    --     V_SDAD_BILL_ID       NUMBER;
    --     V_TOTAL_COUNT        NUMBER := 0;
    --     V_PAID_COUNT         NUMBER := 0;
    --     V_ERROR_MSG          VARCHAR2(4000);
    --     V_ERROR_COUNT        NUMBER := 0;
    --     V_SUCCESS_COUNT      NUMBER := 0;
    --     V_DUP_COUNT          NUMBER := 0;
    --     V_RESULT             VARCHAR2(4000);
    --     V_RECEIPT_RESULT     VARCHAR2(4000);

    --     CURSOR C_LOG IS
    --         SELECT *
    --         FROM   SADAD_WF_LOG
    --         WHERE  WF_ID = P_WF_ID
    --           AND  REQUEST_TYPE = 'BILL_PAYMENT'
    --           AND  SADAD_RESPONSE = 'PAID'
    --         ORDER BY ACTION_DATE DESC;
    -- BEGIN
    --     SELECT COUNT(1),
    --            COUNT(CASE WHEN SADAD_RESPONSE = 'PAID' THEN 1 END)
    --     INTO   V_TOTAL_COUNT, V_PAID_COUNT
    --     FROM   SADAD_WF_LOG
    --     WHERE  WF_ID = P_WF_ID
    --       AND  REQUEST_TYPE = 'BILL_PAYMENT';

    --     IF V_TOTAL_COUNT = 0 THEN
    --         RETURN 'ZERO_AMOUNT_NO_PAYMENT';
    --     END IF;

    --     IF V_PAID_COUNT = 0 THEN
    --         RAISE_APPLICATION_ERROR(
    --             -20010,
    --             'NO PAID BILL PAYMENT RECORDS FOUND FOR WF_ID = ' || P_WF_ID
    --         );
    --     END IF;

    --     FOR L IN C_LOG LOOP
    --         BEGIN
    --             V_RESULT             := NULL;
    --             V_DUPLICATE_CHECK    := 0;
    --             V_UNPAID_BILLS_COUNT := 0;
    --             V_PAYMENT_REMAIN     := 0;
    --             V_RECEIPT_RESULT     := NULL;

    --             -- SAVEPOINT SP_RECORD;

    --             -- SDAD_PKG.UPDATE_SADAD_LOG_STATUS(P_LOG_ID => L.LOG_ID, P_STATUS => 'RUNNING'); --replace with wf_log

    --             IF L.BILL_PROCESS_STATUS = 3 THEN

    --                 SELECT COUNT(1) INTO V_DUPLICATE_CHECK
    --                 FROM   AR_RECEIPT
    --                 WHERE  SADAD_PAYMENT_ID = L.SADAD_PAYMENT_ID;

    --                 IF V_DUPLICATE_CHECK > 0 THEN
    --                     -- SDAD_PKG.UPDATE_SADAD_LOG_STATUS(P_LOG_ID => L.LOG_ID, P_STATUS => 'DUPLICATE_PAYMENT');--replace with wf_log
    --                     V_DUP_COUNT := V_DUP_COUNT + 1;
    --                     V_RESULT    := 'DUPLICATE_PAYMENT';
    --                     CONTINUE;
    --                 END IF;

    --                 IF L.SADAD_PAYMENT_ID IS NULL THEN
    --                     RAISE_APPLICATION_ERROR(-20008, 'SADAD_PAYMENT_ID IS NULL');
    --                 END IF;

    --                 SELECT COUNT(1) INTO V_UNPAID_BILLS_COUNT
    --                 FROM   AR_INVOICE_SDAD_BILLS
    --                 WHERE  BILL_CYCLE = L.BILL_CYCLE
    --                   AND  NVL(PAYED_AMOUNT, 0) = 0;

    --                 IF V_UNPAID_BILLS_COUNT > 0 THEN
    --                     -------------------------------------------------
    --                     UPDATE AR_INVOICE_SDAD_BILLS
    --                     SET PAYED_AMOUNT = L.AMOUNT,
    --                         PAYMENT_DATE = L.ACTION_DATE,
    --                         PAY_REQ_ID   = L.SADAD_PAYMENT_ID,
    --                         STATUS       = L.REQUEST_TYPE,
    --                         PAY_REQ_TYPE = L.REQUEST_TYPE,
    --                         ACTION_DATE  = SYSTIMESTAMP,
    --                         DIFF         = NVL(BILL_AMOUNT, 0) - NVL(L.AMOUNT, 0),
    --                         WORKFLOW_ID  = P_WF_ID
    --                     WHERE BILL_CYCLE = L.BILL_CYCLE
    --                       AND PAYED_AMOUNT = 0;

    --                     V_RECEIPT_RESULT := SDAD_PKG.CREATE_AR_RECEIPT_FROM_SADAD(
    --                         P_ACCOUNT_NUMBER   => L.ACCOUNT_NUMBER,
    --                         P_BILL_CYCLE       => L.BILL_CYCLE,
    --                         P_PAID_AMOUNT      => L.AMOUNT,
    --                         P_SADAD_PAYMENT_ID => L.SADAD_PAYMENT_ID,
    --                         P_RECEIPT_DATE     => L.ACTION_DATE,
    --                         p_description_l1   => 'WF_SADAD_FULL_PAYMENT',
    --                         p_description_l2   => 'WF_SADAD_FULL_PAYMENT'
    --                     );

    --                     IF V_RECEIPT_RESULT != 'DONE' THEN
    --                         RAISE_APPLICATION_ERROR(-20011,
    --                             'RECEIPT CREATION FAILED FOR FULL PAYMENT: ' || V_RECEIPT_RESULT);
    --                     END IF;

    --                     REFRESH_DWH_AFTER_PAYMENT(
    --                         P_WF_ID            => P_WF_ID,
    --                         P_LOG_ID           => L.LOG_ID,
    --                         P_ACCOUNT_NUMBER   => L.ACCOUNT_NUMBER,
    --                         P_AMOUNT           => L.AMOUNT,
    --                         P_BILL_CYCLE       => L.BILL_CYCLE,
    --                         P_SADAD_PAYMENT_ID => L.SADAD_PAYMENT_ID,
    --                         P_REQUEST_TYPE     => L.REQUEST_TYPE,
    --                         P_ACTION_DATE      => L.ACTION_DATE,
    --                         P_PAYMENT_KIND     => 'FULL'
    --                     );

    --                     V_RESULT := 'SUCCESS';

    --                 ELSE
    --                     -------------------------------------------------
    --                     SELECT NVL(
    --                         (SUM(B.AMOUNT_DUE) / COUNT(1)) - SUM(NVL(S.PAYED_AMOUNT, 0)), 0)
    --                     INTO V_PAYMENT_REMAIN
    --                     FROM   AR_INVOICE_SDAD_BILLS S
    --                     JOIN   BILLS B ON S.BILL_CYCLE = B.BILL_CYCLE
    --                     WHERE  S.BILL_CYCLE = L.BILL_CYCLE
    --                       AND  NVL(S.PAYED_AMOUNT, 0) != 0;

    --                     INSERT INTO AR_INVOICE_SDAD_BILLS (
    --                         INVOICE_ID, INVOICE_AMOUNT, BILL_CYCLE,
    --                         ACCOUNT_NUMBER, STATUS, PAYED_AMOUNT,
    --                         BILL_AMOUNT, PAYMENT_DATE, PARTIAL_PAYMENT,
    --                         PAY_REQ_TYPE, PAY_REQ_ID, ACTION_DATE,
    --                         DIFF, WORKFLOW_ID
    --                     ) VALUES (
    --                         NULL, L.AMOUNT, L.BILL_CYCLE,
    --                         L.ACCOUNT_NUMBER, L.REQUEST_TYPE, L.AMOUNT,
    --                         (V_PAYMENT_REMAIN - L.AMOUNT), L.ACTION_DATE,
    --                         'YES', L.REQUEST_TYPE, L.SADAD_PAYMENT_ID,
    --                         SYSTIMESTAMP,
    --                         (V_PAYMENT_REMAIN - L.AMOUNT) - L.AMOUNT, P_WF_ID
    --                     ) RETURNING ID INTO V_SDAD_BILL_ID;

    --                     V_RECEIPT_RESULT := SDAD_PKG.CREATE_AR_RECEIPT_FROM_SADAD(
    --                         P_ACCOUNT_NUMBER   => L.ACCOUNT_NUMBER,
    --                         P_BILL_CYCLE       => L.BILL_CYCLE,
    --                         P_PAID_AMOUNT      => L.AMOUNT,
    --                         P_SADAD_PAYMENT_ID => L.SADAD_PAYMENT_ID,
    --                         P_RECEIPT_DATE     => L.ACTION_DATE,
    --                         p_description_l1   => 'PARTIAL_PAYMENT_WF_SADAD',
    --                         p_description_l2   => 'PARTIAL_PAYMENT_WF_SADAD'
    --                     );

    --                     IF V_RECEIPT_RESULT != 'DONE' THEN
    --                         RAISE_APPLICATION_ERROR(-20012,
    --                             'RECEIPT CREATION FAILED FOR PARTIAL PAYMENT: ' || V_RECEIPT_RESULT);
    --                     END IF;

    --                     REFRESH_DWH_AFTER_PAYMENT(
    --                         P_WF_ID            => P_WF_ID,
    --                         P_LOG_ID           => L.LOG_ID,
    --                         P_ACCOUNT_NUMBER   => L.ACCOUNT_NUMBER,
    --                         P_AMOUNT           => L.AMOUNT,
    --                         P_BILL_CYCLE       => L.BILL_CYCLE,
    --                         P_SADAD_PAYMENT_ID => L.SADAD_PAYMENT_ID,
    --                         P_REQUEST_TYPE     => L.REQUEST_TYPE,
    --                         P_ACTION_DATE      => L.ACTION_DATE,
    --                         P_PAYMENT_KIND     => 'PARTIAL'
    --                     );

    --                     V_RESULT := 'SUCCESS';
    --                 END IF;

    --                 IF V_RESULT = 'SUCCESS' THEN
    --                     V_SUCCESS_COUNT := V_SUCCESS_COUNT + 1;
    --                     SDAD_PKG.UPDATE_SADAD_LOG_STATUS(P_LOG_ID => L.LOG_ID, P_STATUS => 'DONE');
    --                 END IF;

    --             ELSE
    --                 V_RESULT      := 'ERROR: Unknown process status ' || L.BILL_PROCESS_STATUS;
    --                 V_ERROR_COUNT := V_ERROR_COUNT + 1;
    --             END IF;

    --         EXCEPTION
    --             WHEN OTHERS THEN
    --                 V_ERROR_COUNT := V_ERROR_COUNT + 1;
    --                 V_ERROR_MSG   := SQLERRM;

    --                 -- ROLLBACK TO SP_RECORD;

    --                 IF V_DUPLICATE_CHECK > 0 THEN
    --                     SDAD_PKG.UPDATE_SADAD_LOG_STATUS(P_LOG_ID => L.LOG_ID, P_STATUS => 'DUPLICATE_PAYMENT');
    --                 ELSE
    --                     SDAD_PKG.UPDATE_SADAD_LOG_STATUS(
    --                         P_LOG_ID        => L.LOG_ID,
    --                         P_STATUS        => 'ERROR',
    --                         P_ERROR_MESSAGE => V_ERROR_MSG
    --                     );
    --                 END IF;

    --                 APP_ERROR_PKG.INS_SM_DB_ERROR(
    --                     P_FROM_MODULE   => 'CLOUD_SADAD',
    --                     P_FROM_OWNER    => 'RUNERP_CODE',
    --                     P_FROM_OBJECT   => 'PROCESS_BILL_PAYMENT',
    --                     P_OBJECT_TYPE   => 'FUNCTION',
    --                     P_ERROR_MESSAGE => V_ERROR_MSG,
    --                     P_ERROR_STMT    => 'REQ_NUMBER = ' || L.BILL_CYCLE ||
    --                                        ' PAY_REQ_ID = ' || L.SADAD_PAYMENT_ID
    --                 );

    --                 V_RESULT := 'ERROR: ' || V_ERROR_MSG;
    --         END;
    --     END LOOP;

    --     IF V_ERROR_COUNT > 0 THEN
    --         RETURN 'PARTIAL_ERROR: SUCCESS=' || V_SUCCESS_COUNT ||
    --                ' ERROR=' || V_ERROR_COUNT || ' DUP=' || V_DUP_COUNT;
    --     ELSIF V_SUCCESS_COUNT > 0 THEN
    --         RETURN 'SUCCESS';
    --     ELSIF V_DUP_COUNT > 0 THEN
    --         RETURN 'DUPLICATE_PAYMENT';
    --     ELSE
    --         RETURN NVL(V_RESULT, 'NO_DATA');
    --     END IF;

    -- END PROCESS_BILL_PAYMENT;
    FUNCTION PROCESS_BILL_PAYMENT(P_WF_ID NUMBER) RETURN VARCHAR2 IS
        V_DUPLICATE_CHECK    NUMBER := 0;
        V_UNPAID_BILLS_COUNT NUMBER := 0;
        --V_PAYMENT_REMAIN
        V_BILL_TOTAL         NUMBER := 0;
        V_PAID_SO_FAR        NUMBER := 0;   -- Total amount paid before the current payment
        V_REMAIN_AFTER       NUMBER := 0;
        V_SDAD_BILL_ID       NUMBER;
        V_TOTAL_COUNT        NUMBER := 0;
        V_PAID_COUNT         NUMBER := 0;
        V_ERROR_MSG          VARCHAR2(4000);
        V_ERROR_COUNT        NUMBER := 0;
        V_SUCCESS_COUNT      NUMBER := 0;
        V_DUP_COUNT          NUMBER := 0;
        V_RESULT             VARCHAR2(4000);
        V_RECEIPT_RESULT     VARCHAR2(4000);

        CURSOR C_LOG IS
            SELECT *
            FROM   SADAD_WF_LOG
            WHERE  WF_ID = P_WF_ID
              AND  REQUEST_TYPE = 'BILL_PAYMENT'
              AND  SADAD_RESPONSE = 'PAID'
            ORDER BY ACTION_DATE DESC;
    BEGIN
        SELECT COUNT(1),
               COUNT(CASE WHEN SADAD_RESPONSE = 'PAID' THEN 1 END)
        INTO   V_TOTAL_COUNT, V_PAID_COUNT
        FROM   SADAD_WF_LOG
        WHERE  WF_ID = P_WF_ID
          AND  REQUEST_TYPE = 'BILL_PAYMENT';

        IF V_TOTAL_COUNT = 0 THEN
            RETURN 'ZERO_AMOUNT_NO_PAYMENT';
        END IF;

        IF V_PAID_COUNT = 0 THEN
            RAISE_APPLICATION_ERROR(
                -20010,
                'NO PAID BILL PAYMENT RECORDS FOUND FOR WF_ID = ' || P_WF_ID
            );
        END IF;

        FOR L IN C_LOG LOOP
            BEGIN
                V_RESULT             := NULL;
                V_DUPLICATE_CHECK    := 0;
                V_UNPAID_BILLS_COUNT := 0;
                V_BILL_TOTAL         := 0;
                V_PAID_SO_FAR        := 0;
                V_REMAIN_AFTER       := 0;
                V_RECEIPT_RESULT     := NULL;

                -- SDAD_PKG.UPDATE_SADAD_LOG_STATUS(P_LOG_ID => L.LOG_ID, P_STATUS => 'RUNNING'); --replace with wf_log

                IF L.BILL_PROCESS_STATUS = 3 THEN

                    SELECT COUNT(1) INTO V_DUPLICATE_CHECK
                    FROM   AR_RECEIPT
                    WHERE  SADAD_PAYMENT_ID = L.SADAD_PAYMENT_ID;

                    IF V_DUPLICATE_CHECK > 0 THEN
                        -- SDAD_PKG.UPDATE_SADAD_LOG_STATUS(P_LOG_ID => L.LOG_ID, P_STATUS => 'DUPLICATE_PAYMENT');--replace with wf_log
                        V_DUP_COUNT := V_DUP_COUNT + 1;
                        V_RESULT    := 'DUPLICATE_PAYMENT';
                        CONTINUE;
                    END IF;

                    IF L.SADAD_PAYMENT_ID IS NULL THEN
                        RAISE_APPLICATION_ERROR(-20008, 'SADAD_PAYMENT_ID IS NULL');
                    END IF;

                    SELECT NVL(SUM(AMOUNT_DUE), 0)
                    INTO   V_BILL_TOTAL
                    FROM   BILLS
                    WHERE  BILL_CYCLE = L.BILL_CYCLE;

                    -- Total amount paid before the current payment
                    SELECT NVL(SUM(PAYED_AMOUNT), 0)
                    INTO   V_PAID_SO_FAR
                    FROM   AR_INVOICE_SDAD_BILLS
                    WHERE  BILL_CYCLE = L.BILL_CYCLE
                      AND  NVL(PAYED_AMOUNT, 0) <> 0;

                    V_REMAIN_AFTER := V_BILL_TOTAL - V_PAID_SO_FAR - L.AMOUNT;

                    SELECT COUNT(1) INTO V_UNPAID_BILLS_COUNT
                    FROM   AR_INVOICE_SDAD_BILLS
                    WHERE  BILL_CYCLE = L.BILL_CYCLE
                      AND  NVL(PAYED_AMOUNT, 0) = 0;

                    IF V_UNPAID_BILLS_COUNT > 0 THEN
                        -------------------------------------------------
                        -- Branch (A): First payment on an existing ready record -> UPDATE
                        -------------------------------------------------

                        UPDATE AR_INVOICE_SDAD_BILLS
                        SET PAYED_AMOUNT    = L.AMOUNT,
                            BILL_AMOUNT     = V_BILL_TOTAL,
                            DIFF            = V_REMAIN_AFTER,
                            PARTIAL_PAYMENT = CASE WHEN V_REMAIN_AFTER > 0 THEN 'YES' ELSE 'NO' END,
                            PAYMENT_DATE    = L.ACTION_DATE,
                            PAY_REQ_ID      = L.SADAD_PAYMENT_ID,
                            STATUS          = L.REQUEST_TYPE,
                            PAY_REQ_TYPE    = L.REQUEST_TYPE,
                            ACTION_DATE     = SYSTIMESTAMP,
                            WORKFLOW_ID     = P_WF_ID
                        WHERE BILL_CYCLE = L.BILL_CYCLE
                        AND PAYED_AMOUNT = 0;

                        -- WHERE ID = (
                        --           SELECT ID FROM (
                        --               SELECT ID
                        --               FROM   AR_INVOICE_SDAD_BILLS
                        --               WHERE  BILL_CYCLE = L.BILL_CYCLE
                        --                 AND  NVL(PAYED_AMOUNT, 0) = 0
                        --               ORDER BY ID
                        --           )
                        --           WHERE ROWNUM = 1
                        --       );


                        V_RECEIPT_RESULT := SDAD_PKG.CREATE_AR_RECEIPT_FROM_SADAD(
                            P_ACCOUNT_NUMBER   => L.ACCOUNT_NUMBER,
                            P_BILL_CYCLE       => L.BILL_CYCLE,
                            P_PAID_AMOUNT      => L.AMOUNT,
                            P_SADAD_PAYMENT_ID => L.SADAD_PAYMENT_ID,
                            P_RECEIPT_DATE     => L.ACTION_DATE,
                            p_description_l1   => 'WF_SADAD_FIRST_PAYMENT',

                            p_description_l2   => 'WF_SADAD_FIRST_PAYMENT'
                        );

                        IF V_RECEIPT_RESULT != 'DONE' THEN
                            RAISE_APPLICATION_ERROR(-20011,
                                'RECEIPT CREATION FAILED FOR FIRST PAYMENT: ' || V_RECEIPT_RESULT);
                        END IF;

                        REFRESH_DWH_AFTER_PAYMENT(
                            P_WF_ID            => P_WF_ID,
                            P_LOG_ID           => L.LOG_ID,
                            P_ACCOUNT_NUMBER   => L.ACCOUNT_NUMBER,
                            P_AMOUNT           => L.AMOUNT,
                            P_BILL_CYCLE       => L.BILL_CYCLE,
                            P_SADAD_PAYMENT_ID => L.SADAD_PAYMENT_ID,
                            P_REQUEST_TYPE     => L.REQUEST_TYPE,
                            P_ACTION_DATE      => L.ACTION_DATE,
                            P_PAYMENT_KIND     => CASE WHEN V_REMAIN_AFTER > 0 THEN 'PARTIAL' ELSE 'FULL' END
                        );
                         -- add wf_log here

                        V_RESULT := 'SUCCESS';

                    ELSE
                        -------------------------------------------------
                        -- Branch (B): Additional payment after the cycle is fully paid -> INSERT
                        -------------------------------------------------
                        INSERT INTO AR_INVOICE_SDAD_BILLS (
                            INVOICE_ID, INVOICE_AMOUNT, BILL_CYCLE,
                            ACCOUNT_NUMBER, STATUS, PAYED_AMOUNT,
                            BILL_AMOUNT, PAYMENT_DATE, PARTIAL_PAYMENT,
                            PAY_REQ_TYPE, PAY_REQ_ID, ACTION_DATE,
                            DIFF, WORKFLOW_ID
                        ) VALUES (
                            NULL,
                            V_BILL_TOTAL,
                            L.BILL_CYCLE,
                            L.ACCOUNT_NUMBER,
                            L.REQUEST_TYPE,
                            L.AMOUNT,
                            V_BILL_TOTAL,
                            L.ACTION_DATE,
                            CASE WHEN V_REMAIN_AFTER > 0 THEN 'YES' ELSE 'NO' END,
                            L.REQUEST_TYPE,
                            L.SADAD_PAYMENT_ID,
                            SYSTIMESTAMP,
                            V_REMAIN_AFTER,
                            P_WF_ID
                        ) RETURNING ID INTO V_SDAD_BILL_ID;

                        V_RECEIPT_RESULT := SDAD_PKG.CREATE_AR_RECEIPT_FROM_SADAD( -- will transfer to SDAD_portal_PKG 17-06-2026
                            P_ACCOUNT_NUMBER   => L.ACCOUNT_NUMBER,

                            P_BILL_CYCLE       => L.BILL_CYCLE,
                            P_PAID_AMOUNT      => L.AMOUNT,
                            P_SADAD_PAYMENT_ID => L.SADAD_PAYMENT_ID,
                            P_RECEIPT_DATE     => L.ACTION_DATE,
                            p_description_l1   => 'ADDITIONAL_PAYMENT_WF_SADAD',
                            p_description_l2   => 'ADDITIONAL_PAYMENT_WF_SADAD'
                        );

                        IF V_RECEIPT_RESULT != 'DONE' THEN
                            RAISE_APPLICATION_ERROR(-20012,
                                'RECEIPT CREATION FAILED FOR ADDITIONAL PAYMENT: ' || V_RECEIPT_RESULT);
                        END IF;

                        REFRESH_DWH_AFTER_PAYMENT(
                            P_WF_ID            => P_WF_ID,
                            P_LOG_ID           => L.LOG_ID,
                            P_ACCOUNT_NUMBER   => L.ACCOUNT_NUMBER,
                            P_AMOUNT           => L.AMOUNT,
                            P_BILL_CYCLE       => L.BILL_CYCLE,
                            P_SADAD_PAYMENT_ID => L.SADAD_PAYMENT_ID,
                            P_REQUEST_TYPE     => L.REQUEST_TYPE,
                            P_ACTION_DATE      => L.ACTION_DATE,
                            P_PAYMENT_KIND     => CASE WHEN V_REMAIN_AFTER > 0 THEN 'PARTIAL' ELSE 'FULL' END
                        );

                        -- add wf_log here

                        V_RESULT := 'SUCCESS';
                    END IF;

                    IF V_RESULT = 'SUCCESS' THEN
                        V_SUCCESS_COUNT := V_SUCCESS_COUNT + 1;
                        SDAD_PKG.UPDATE_SADAD_LOG_STATUS(P_LOG_ID => L.LOG_ID, P_STATUS => 'DONE');
                    END IF;

                ELSE
                    V_RESULT      := 'ERROR: Unknown process status ' || L.BILL_PROCESS_STATUS;
                    V_ERROR_COUNT := V_ERROR_COUNT + 1;
                END IF;

            EXCEPTION
                WHEN OTHERS THEN
                    V_ERROR_COUNT := V_ERROR_COUNT + 1;
                    V_ERROR_MSG   := SQLERRM;

                    IF V_DUPLICATE_CHECK > 0 THEN
                        SDAD_PKG.UPDATE_SADAD_LOG_STATUS(P_LOG_ID => L.LOG_ID, P_STATUS => 'DUPLICATE_PAYMENT');
                    ELSE
                        SDAD_PKG.UPDATE_SADAD_LOG_STATUS(
                            P_LOG_ID        => L.LOG_ID,
                            P_STATUS        => 'ERROR',
                            P_ERROR_MESSAGE => V_ERROR_MSG
                        );
                    END IF;

                    APP_ERROR_PKG.INS_SM_DB_ERROR(
                        P_FROM_MODULE   => 'CLOUD_SADAD',
                        P_FROM_OWNER    => 'RUNERP_CODE',
                        P_FROM_OBJECT   => 'PROCESS_BILL_PAYMENT',
                        P_OBJECT_TYPE   => 'FUNCTION',
                        P_ERROR_MESSAGE => V_ERROR_MSG,
                        P_ERROR_STMT    => 'REQ_NUMBER = ' || L.BILL_CYCLE ||
                                           ' PAY_REQ_ID = ' || L.SADAD_PAYMENT_ID
                    );

                    V_RESULT := 'ERROR: ' || V_ERROR_MSG;
            END;
        END LOOP;

        IF V_ERROR_COUNT > 0 THEN
            RETURN 'PARTIAL_ERROR: SUCCESS=' || V_SUCCESS_COUNT ||
                   ' ERROR=' || V_ERROR_COUNT || ' DUP=' || V_DUP_COUNT;
        ELSIF V_SUCCESS_COUNT > 0 THEN
            RETURN 'SUCCESS';
        ELSIF V_DUP_COUNT > 0 THEN
            RETURN 'DUPLICATE_PAYMENT';
        ELSE
            RETURN NVL(V_RESULT, 'NO_DATA');
        END IF;

    END PROCESS_BILL_PAYMENT;
    -- ====================================================================
PROCEDURE CREATE_LIVEIN_ORDER(
    P_TERMS_AND_CONDITIONS    IN VARCHAR2,
    P_INDV_SAL_QUOT_ID        IN NUMBER,
    P_SESSION_POT_CUST_ID     IN NUMBER,
    P_CUSTOMER_ID             IN OUT NUMBER,
    P_SESSION_USER_ID         IN NUMBER,
    P_CUSTOMER_FIRST_NAME     IN VARCHAR2,
    P_CUSTOMER_LAST_NAME      IN VARCHAR2,
    P_CUSTOMER_ADDRESS        IN VARCHAR2,
    P_CUSTOMER_IDENT_ID       IN NUMBER,
    P_WORK_SKILL              IN NUMBER,
    P_REFE_CUST_CONTRACT_ID   IN NUMBER DEFAULT NULL,
    P_WORKED_BEFORE           IN VARCHAR2,
    P_SALES_CODE              IN VARCHAR2,
    P_EMP_ID                  IN NUMBER DEFAULT NULL,
    P_SHOWROOM                IN NUMBER,
    P_COMBINATION_CODE        IN VARCHAR2 DEFAULT NULL,
    P_VISIT_DATA_JSON         IN CLOB DEFAULT NULL,
    P_ADDRESS_ID              IN NUMBER DEFAULT NULL,
    P_CONTRACT_SYMBOL         OUT VARCHAR2
) IS
    L_CUST_SITE_ID              NUMBER;
    L_MOBILE                    VARCHAR2(15);
    L_CUST_CONTRACT_ID          NUMBER;
    L_CUST_CONTRACT_DTL_ID      NUMBER;
    V_INDV_SAL_QUOT_NATIONALITY NUMBER;
    L_INDV_RFQ_ID               NUMBER;
    L_RESULT_CONTRACT           VARCHAR2(3000);
BEGIN
    -- 1. Validate Basic Rules
    IF NVL(P_TERMS_AND_CONDITIONS, 'NO') <> 'YES' THEN
        RAISE_APPLICATION_ERROR(-20001, 'ERR_TERMS_NOT_ACCEPTED');
    END IF;

    IF P_INDV_SAL_QUOT_ID IS NULL THEN
        RAISE_APPLICATION_ERROR(-20001, 'ERR_QUOTATION_REQUIRED');
    END IF;

    -- 2. Handle Potential Customer Conversion
    IF P_SESSION_POT_CUST_ID IS NOT NULL AND P_CUSTOMER_ID IS NULL THEN
        BEGIN
            SELECT MOBILE_NO
              INTO L_MOBILE
              FROM SM_USER
             WHERE POT_CUST_ID = P_SESSION_POT_CUST_ID;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                RAISE_APPLICATION_ERROR(-20001, 'ERR_MOBILE_NOT_FOUND');
        END;

        -- Insert AR_CUSTOMER
        INSERT INTO AR_CUSTOMER (
            CUSTOMER_ID, CUSTOMER_SYMBOL, CUSTOMER_NAME_L1,
            CUSTOMER_NAME_L2, INTEREST_TYPE, CUSTOMER_TYPE,
            FULL_ADDRESS, MOBILE, EMAIL
        ) VALUES (
            DML_PKG.GET_NEXT_VALUE('CUSTOMER_ID', 'AR_CUSTOMER'),
            -- Note: V('...') functions are not used because API requests do not have APEX sessions.
            SM_SYMBOL_PKG.GET_NEXTVAL('AR_INDV_CUSTOMER', SM_SETTING_PKG.GET_DEFAULT_OP_UNIT_ID(P_SESSION_USER_ID, SM_SETTING_PKG.GET_CURRENT_RESP_ID), 'SOB'),
            P_CUSTOMER_FIRST_NAME || ' ' || P_CUSTOMER_LAST_NAME,
            P_CUSTOMER_FIRST_NAME || ' ' || P_CUSTOMER_LAST_NAME,
            'NONE', 'PERSON', P_CUSTOMER_ADDRESS, L_MOBILE, NULL
        ) RETURNING CUSTOMER_ID INTO P_CUSTOMER_ID;

        -- Insert AR_CUSTOMER_SITE
        INSERT INTO AR_CUSTOMER_SITE (
            CUST_SITE_ID, INDV_F_NAME, INDV_L_NAME, CUSTOMER_ID,
            FULL_ADDRESS, MOBILE, INDV_ID_NUMBER, INTEREST_TYPE
        ) VALUES (
            DML_PKG.GET_NEXT_VALUE('CUST_SITE_ID', 'AR_CUSTOMER_SITE'),
            P_CUSTOMER_FIRST_NAME, P_CUSTOMER_LAST_NAME, P_CUSTOMER_ID,
            P_CUSTOMER_ADDRESS, L_MOBILE, P_CUSTOMER_IDENT_ID, 'NONE'
        ) RETURNING CUST_SITE_ID INTO L_CUST_SITE_ID;

        -- Convert
        AR_POTENTIAL_CUSTOMER_PKG.CONVERT_POT_TO_CUSTOMER(
            P_POT_CUST_ID  => P_SESSION_POT_CUST_ID,
            P_CUSTOMER_ID  => P_CUSTOMER_ID,
            P_CUST_SITE_ID => L_CUST_SITE_ID,
            P_SECTION_TYPE => 'PERSON'
        );
    ELSE
        -- Existing customer logic to fetch site
        BEGIN
            SELECT CUST_SITE_ID INTO L_CUST_SITE_ID
              FROM AR_CUSTOMER_SITE
             WHERE CUSTOMER_ID = P_CUSTOMER_ID
             FETCH FIRST ROW ONLY;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                RAISE_APPLICATION_ERROR(-20001, 'ERR_CUST_SITE_NOT_FOUND');
        END;
    END IF;

    -- 3. Fetch Nationality ID from Quotation
    SELECT NVL(NATIONALITY_ID, '')
      INTO V_INDV_SAL_QUOT_NATIONALITY
      FROM INDV_SAL_QUOTATION
     WHERE INDV_SAL_QUOT_ID = P_INDV_SAL_QUOT_ID;

    -- 4. Create RFQ Request
    L_INDV_RFQ_ID := TO_NUMBER(INDV_SAL_REQUEST_PKG.CREATE_REQUEST(
        P_CUST_SITE_ID     => L_CUST_SITE_ID,
        P_INDV_SAL_QUOT_ID => P_INDV_SAL_QUOT_ID,
        P_WORK_SKILL       => P_WORK_SKILL,
        P_WORKED_BEFORE    => P_WORKED_BEFORE,
        P_SOURCE           => 'CUSTOMER',
        P_POTENTIAL_ID     => P_SESSION_POT_CUST_ID,
        P_RETURN_ID        => 'YES',
        P_SALES_CODE_ID    => AR_SALES_CODE_PKG.GET_CODE_ID(TRIM(P_SALES_CODE)),
        P_SALES_CODE       => P_SALES_CODE,
        P_RFQ_EMP_ID       => P_EMP_ID,
        P_SHOWROOM         => P_SHOWROOM,
        P_NATIONALITY_ID   => V_INDV_SAL_QUOT_NATIONALITY,
        P_COMBINATION_CODE => P_COMBINATION_CODE,
        P_VISIT_DATA_JSON  => P_VISIT_DATA_JSON,
        P_ADDRESS_ID       => P_ADDRESS_ID
    ));

    -- 5. Create Contract
    L_RESULT_CONTRACT := INDIVIDUAL_SAL_CONTRACT_PKG.CREATE_CONTRACT2(
        P_INDV_RFQ_ID           => L_INDV_RFQ_ID,
        P_REF_CUST_CONTRACT_ID  => P_REFE_CUST_CONTRACT_ID,
        P_CONTRACT_SYMBOL       => P_CONTRACT_SYMBOL,
        P_CREATED_WITH_SADAD    => 'YES',
        P_CREATE_WITH_SADAD_INS => 'YES',
        P_CREATE_WITH_SADAD_DEP => 'YES'
    );

    IF L_RESULT_CONTRACT IS NULL OR L_RESULT_CONTRACT <> 'DONE' THEN
        RAISE_APPLICATION_ERROR(-20001, 'ERR_CONTRACT_CREATION_FAILED');
    END IF;

    -- 6. Reserve Labor
    SELECT C.CUST_CONTRACT_ID
      INTO L_CUST_CONTRACT_ID
      FROM REC_CUST_CONTRACT C
     WHERE C.INDV_RFQ_ID = L_INDV_RFQ_ID
     FETCH FIRST ROW ONLY;

    SELECT CUST_CONTRACT_DTL_ID
      INTO L_CUST_CONTRACT_DTL_ID
      FROM REC_CUST_CONTRACT_DTL
     WHERE CUST_CONTRACT_ID = L_CUST_CONTRACT_ID
     FETCH FIRST ROW ONLY;

    IF P_EMP_ID IS NOT NULL THEN
        CMP_CAMP_OCCUPANCY_PKG.RESERVE_LABOR(
            P_EMP_ID           => P_EMP_ID,
            P_CUST_CONTRACT_ID => L_CUST_CONTRACT_ID
        );
    END IF;

EXCEPTION
    WHEN NO_DATA_FOUND THEN
        ABSH_UTIL_PKG.LOG_ERROR(SQLERRM, SQLCODE, DBMS_UTILITY.FORMAT_ERROR_BACKTRACE, 'ABSH_CREATE_ORDER.CREATE_LIVEIN_ORDER');
        RAISE;
    WHEN OTHERS THEN
        ABSH_UTIL_PKG.LOG_ERROR(SQLERRM, SQLCODE, DBMS_UTILITY.FORMAT_ERROR_BACKTRACE, 'ABSH_CREATE_ORDER.CREATE_LIVEIN_ORDER');
        RAISE;
END CREATE_LIVEIN_ORDER;

END "ABSH_CREATE_ORDER";


/
