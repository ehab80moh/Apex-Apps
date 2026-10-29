
  CREATE OR REPLACE EDITIONABLE FUNCTION "EPROMHQ"."CHECK_APPROVER_EXISTS" (
    p_app_user VARCHAR2
) RETURN NUMBER IS
    v_count  NUMBER := 0;
    v_count2 NUMBER := 0;
BEGIN
    -- Sum the counts from both tables
    SELECT NVL(SUM(C1.CNT), 0) + NVL(SUM(C2.CNT), 0)
    INTO v_count
    FROM (
        SELECT COUNT(*) AS CNT
        FROM central.APR_APPROVAL_RESULTS_CUST_F F
        WHERE F.APPROVER = p_app_user
    ) C1,
    (
        SELECT COUNT(*) AS CNT
        FROM EPROMHQ.VAC_APPROVERS A
        WHERE p_app_user IN (
            SELECT column_value
            FROM TABLE(APEX_STRING.SPLIT(A.APPROVER, ':'))
        )
     --   OR p_app_user IN ('1971','1825','3199')
    ) C2;

    -- Pending tasks
    SELECT COUNT(*)
    INTO v_count2
    FROM TABLE (
        apex_approval.get_tasks (
            p_context            => 'MY_TASKS',
            p_show_expired_tasks => 'Y'
        )
    ) t1
    WHERE t1.state IN ('Assigned', 'Unassigned');

    -- Return 1 if approver exists / has tasks, else 0
    RETURN CASE
        WHEN v_count2 + v_count > 0 THEN 1
        ELSE 0
    END;

EXCEPTION
    WHEN NO_DATA_FOUND THEN
        RETURN 0;  -- مفيش بيانات = كأنه مش موجود
    WHEN TOO_MANY_ROWS THEN
        RETURN 1;  -- لو حصل تكرار، نعتبره موجود
    WHEN OTHERS THEN
        -- أي خطأ غير متوقع: نكتب في log أو نرجع 0
        DBMS_OUTPUT.PUT_LINE('Error in CHECK_APPROVER_EXISTS: ' || SQLERRM);
        RETURN 0;
END;
/
