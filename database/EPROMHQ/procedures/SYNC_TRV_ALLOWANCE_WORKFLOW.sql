
  CREATE OR REPLACE EDITIONABLE PROCEDURE "EPROMHQ"."SYNC_TRV_ALLOWANCE_WORKFLOW"
IS
BEGIN
    -------------------------------------------------------------------
    -- منع Audit Trigger أثناء تشغيل البروسيدجر فقط
    -------------------------------------------------------------------
    EPROMHQ.TRV_TRIGGER_CONTROL.G_SKIP_ALLOWANCE_AUDIT := TRUE;

delete EPROMHQ.TRV_ALLOWANCE_WF_LOG;
    -------------------------------------------------------------------
    -- 1) تحديث STATUS
    -- التحديث يتم فقط لو القيمة الجديدة مختلفة عن القيمة الحالية
    -------------------------------------------------------------------
    UPDATE EPROMHQ.TRV_ALLOWANCE T
       SET T.STATUS =
           (
               SELECT W.STATE_CODE
                 FROM APEX_WORKFLOWS W
                WHERE TO_CHAR(W.WORKFLOW_ID) =
                      TO_CHAR(T.WORKFLOW_ID)
           )
     WHERE T.WORKFLOW_ID IS NOT NULL
       AND NOT (NVL(T.APPROVAL_FINANCE, '0') = '2'
                AND NVL(T.DELETE_APPROVAL_FINANCE, 0) = 1)

       AND EXISTS
           (
               SELECT 1
                 FROM APEX_WORKFLOWS W
                WHERE TO_CHAR(W.WORKFLOW_ID) =
                      TO_CHAR(T.WORKFLOW_ID)

                  AND DECODE(
                          T.STATUS,
                          W.STATE_CODE, 0,
                          1
                      ) = 1
           );


    -------------------------------------------------------------------
    -- 2) إضافة Log لـ REQUEST_TYPE_ID = 33
    --
    -- يتم الإدخال فقط إذا:
    -- Workflow مكتمل
    -- APPROVAL_MANAGER فارغ
    -- أو APPROVAL_CAR فارغ
    -- ولم يتم تسجيل نفس الحالة قبل ذلك
    -------------------------------------------------------------------
    INSERT INTO EPROMHQ.TRV_ALLOWANCE_WF_LOG
    (
        REQUEST_ID,
        WORKFLOW_ID,
        REQUEST_TYPE_ID,
        WORKFLOW_STATE,
        WORKFLOW_STATE_CODE,
        APPROVAL_MANAGER,
        APPROVAL_CAR,
        APPROVAL_HOTEL,
        MISSING_REASON
    )
    SELECT T.REQUEST_ID,
           T.WORKFLOW_ID,
           T.REQUEST_TYPE_ID,
           W.STATE,
           W.STATE_CODE,
           T.APPROVAL_MANAGER,
           T.APPROVAL_CAR,
           T.APPROVAL_HOTEL,

           TRIM(
               CASE
                   WHEN T.APPROVAL_MANAGER IS NULL
                   THEN 'APPROVAL_MANAGER IS NULL; '
               END
               ||
               CASE
                   WHEN T.APPROVAL_CAR IS NULL
                   THEN 'APPROVAL_CAR IS NULL; '
               END
           ) AS MISSING_REASON

      FROM EPROMHQ.TRV_ALLOWANCE T

      JOIN APEX_WORKFLOWS W
        ON TO_CHAR(W.WORKFLOW_ID) =
           TO_CHAR(T.WORKFLOW_ID)

     WHERE T.REQUEST_TYPE_ID = 33

       AND UPPER(W.STATE) = 'COMPLETED'

       AND
       (
              T.APPROVAL_MANAGER IS NULL
           OR T.APPROVAL_CAR IS NULL
       )

       AND NOT EXISTS
       (
           SELECT 1
             FROM EPROMHQ.TRV_ALLOWANCE_WF_LOG L
            WHERE L.REQUEST_ID = T.REQUEST_ID

              AND TO_CHAR(L.WORKFLOW_ID) =
                  TO_CHAR(T.WORKFLOW_ID)

              AND NVL(L.WORKFLOW_STATE, '-') =
                  NVL(W.STATE, '-')

              AND NVL(L.WORKFLOW_STATE_CODE, '-') =
                  NVL(W.STATE_CODE, '-')
       );


    -------------------------------------------------------------------
    -- 3) إضافة Log لـ REQUEST_TYPE_ID = 47
    --
    -- يتم الإدخال فقط إذا:
    -- Workflow مكتمل
    -- APPROVAL_MANAGER فارغ
    -- أو APPROVAL_CAR فارغ
    -- أو APPROVAL_HOTEL فارغ
    -- ولم يتم تسجيل نفس الحالة قبل ذلك
    -------------------------------------------------------------------
    INSERT INTO EPROMHQ.TRV_ALLOWANCE_WF_LOG
    (
        REQUEST_ID,
        WORKFLOW_ID,
        REQUEST_TYPE_ID,
        WORKFLOW_STATE,
        WORKFLOW_STATE_CODE,
        APPROVAL_MANAGER,
        APPROVAL_CAR,
        APPROVAL_HOTEL,
        MISSING_REASON
    )
    SELECT T.REQUEST_ID,
           T.WORKFLOW_ID,
           T.REQUEST_TYPE_ID,
           W.STATE,
           W.STATE_CODE,
           T.APPROVAL_MANAGER,
           T.APPROVAL_CAR,
           T.APPROVAL_HOTEL,

           TRIM(
               CASE
                   WHEN T.APPROVAL_MANAGER IS NULL
                   THEN 'APPROVAL_MANAGER IS NULL; '
               END
               ||
               CASE
                   WHEN T.APPROVAL_CAR IS NULL
                   THEN 'APPROVAL_CAR IS NULL; '
               END
               ||
               CASE
                   WHEN T.APPROVAL_HOTEL IS NULL
                   THEN 'APPROVAL_HOTEL IS NULL; '
               END
           ) AS MISSING_REASON

      FROM EPROMHQ.TRV_ALLOWANCE T

      JOIN APEX_WORKFLOWS W
        ON TO_CHAR(W.WORKFLOW_ID) =
           TO_CHAR(T.WORKFLOW_ID)

     WHERE T.REQUEST_TYPE_ID = 47

       AND UPPER(W.STATE) = 'COMPLETED'

       AND
       (
              T.APPROVAL_MANAGER IS NULL
           OR T.APPROVAL_CAR IS NULL
           OR T.APPROVAL_HOTEL IS NULL
       )

       AND NOT EXISTS
       (
           SELECT 1
             FROM EPROMHQ.TRV_ALLOWANCE_WF_LOG L
            WHERE L.REQUEST_ID = T.REQUEST_ID

              AND TO_CHAR(L.WORKFLOW_ID) =
                  TO_CHAR(T.WORKFLOW_ID)

              AND NVL(L.WORKFLOW_STATE, '-') =
                  NVL(W.STATE, '-')

              AND NVL(L.WORKFLOW_STATE_CODE, '-') =
                  NVL(W.STATE_CODE, '-')
       );


    -------------------------------------------------------------------
    -- 4) تحديث TASK_IDS
    -- يتم التحديث فقط لو قائمة المهام الجديدة مختلفة عن الحالية
    -------------------------------------------------------------------
    UPDATE EPROMHQ.TRV_ALLOWANCE T
       SET T.TASK_IDS =
           (
               SELECT LISTAGG(
                          TO_CHAR(AT.TASK_ID),
                          ' ==> '
                      )
                      WITHIN GROUP
                      (
                          ORDER BY AT.TASK_ID
                      )
                 FROM APEX_TASKS AT
                WHERE TO_CHAR(AT.WORKFLOW_ID) =
                      TO_CHAR(T.WORKFLOW_ID)
           )

     WHERE T.WORKFLOW_ID IS NOT NULL

       AND EXISTS
       (
           SELECT 1
             FROM
             (
                 SELECT TO_CHAR(AT.WORKFLOW_ID) AS WORKFLOW_ID,

                        LISTAGG(
                            TO_CHAR(AT.TASK_ID),
                            ' ==> '
                        )
                        WITHIN GROUP
                        (
                            ORDER BY AT.TASK_ID
                        ) AS NEW_TASK_IDS

                   FROM APEX_TASKS AT

                  WHERE AT.WORKFLOW_ID IS NOT NULL

                  GROUP BY TO_CHAR(AT.WORKFLOW_ID)
             ) TASK_DATA

            WHERE TASK_DATA.WORKFLOW_ID =
                  TO_CHAR(T.WORKFLOW_ID)

              AND DECODE(
                      T.TASK_IDS,
                      TASK_DATA.NEW_TASK_IDS, 0,
                      1
                  ) = 1
       );


    -------------------------------------------------------------------
    -- إعادة تشغيل Audit Trigger
    -------------------------------------------------------------------
    EPROMHQ.TRV_TRIGGER_CONTROL.G_SKIP_ALLOWANCE_AUDIT := FALSE;

    COMMIT;


EXCEPTION
    WHEN OTHERS THEN
        ----------------------------------------------------------------
        -- ضروري إعادة التريجر للوضع الطبيعي في حالة حدوث خطأ
        ----------------------------------------------------------------
        EPROMHQ.TRV_TRIGGER_CONTROL.G_SKIP_ALLOWANCE_AUDIT := FALSE;

        ROLLBACK;

        RAISE;
END SYNC_TRV_ALLOWANCE_WORKFLOW;
/
