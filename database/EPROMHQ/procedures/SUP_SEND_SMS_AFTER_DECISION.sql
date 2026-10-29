
  CREATE OR REPLACE EDITIONABLE PROCEDURE "EPROMHQ"."SUP_SEND_SMS_AFTER_DECISION" (
    p_supplier_id IN sup_suppliers.supplier_id%TYPE,
    p_current_role IN VARCHAR2,
    p_request      IN VARCHAR2   -- SUBMIT_APPROVAL / SUBMIT_REJECT
)
IS
    l_message        VARCHAR2(500);
    l_next_role      VARCHAR2(10);
    l_result         VARCHAR2(550);
    l_waiting_count  NUMBER;
    l_is_reroute     CHAR(1);
BEGIN
    /* -------------------------------------------------
       Count waiting suppliers (CORRECT & GLOBAL)
    --------------------------------------------------*/
    SELECT COUNT(*)
      INTO l_waiting_count
      FROM sup_suppliers
     WHERE status IN ('ACTIVE','PENDING');

    /* -------------------------------------------------
       Detect reroute after rejection
    --------------------------------------------------*/
    SELECT CASE
             WHEN EXISTS (
                  SELECT 1
                    FROM sup_suppliers
                   WHERE supplier_id = p_supplier_id
                     AND status LIKE '%REJECT%'
             )
             THEN 'Y'
             ELSE 'N'
           END
      INTO l_is_reroute
      FROM dual;

    /* -------------------------------------------------
       Determine next role (ROLE-AWARE)
    --------------------------------------------------*/
    l_next_role :=
        CASE p_current_role
            WHEN 'PROC'  THEN 'TECH'
            WHEN 'TECH'  THEN 'FIN'
            WHEN 'FIN'   THEN 'LEGAL'
            ELSE NULL
        END;

    /* -------------------------------------------------
       Final approval → no SMS
    --------------------------------------------------*/
    IF l_next_role IS NULL THEN
        RETURN;
    END IF;

    /* -------------------------------------------------
       Build SMS message
    --------------------------------------------------*/
    IF p_request = 'SUBMIT_REJECT' THEN

        l_message :=
            'Supplier request was rejected. '
            || l_waiting_count
            || ' supplier(s) waiting.';

    ELSE
        IF l_is_reroute = 'Y' THEN
            l_message :=
                'Supplier request resubmitted after rejection. '
                || l_waiting_count
                || ' supplier(s) waiting for approval.';
        ELSE
            l_message :=
                'New supplier waiting your approval. '
                || l_waiting_count
                || ' supplier(s) in queue.';
        END IF;
    END IF;

    /* -------------------------------------------------
       Send SMS to NEXT ROLE only
    --------------------------------------------------*/
    FOR r IN (
        SELECT DISTINCT ec.mobile
          FROM sup_approval_members m
          JOIN central.emp_contact ec
            ON ec.emp_id = m.employee_num
         WHERE m.approval_role     = l_next_role
           AND m.status            = 'ACTIVE'
           AND ec.mobile_confirmed = 1
           AND ec.mobile IS NOT NULL
    )
    LOOP
        BEGIN
            l_result :=
                central.sms_pkg.send_single(
                    l_message,
                    r.mobile
                );
        EXCEPTION
            WHEN OTHERS THEN
                apex_debug.error(
                    'SMS failed for mobile '
                    || r.mobile
                    || ' : '
                    || SQLERRM
                );
        END;
    END LOOP;

END sup_send_sms_after_decision;
/
