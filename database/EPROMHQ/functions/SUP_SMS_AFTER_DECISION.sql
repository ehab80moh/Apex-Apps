
  CREATE OR REPLACE EDITIONABLE FUNCTION "EPROMHQ"."SUP_SMS_AFTER_DECISION" (
    p_supplier_id   IN NUMBER,
    p_action        IN VARCHAR2,  -- SUBMIT-APPROVAL / SUBMIT-REJECT
    p_current_role  IN VARCHAR2,  -- PROC / TECH / FIN / LEGAL
    p_sender_empno  IN NUMBER     -- Emp_no of the user performing the action
) RETURN VARCHAR2
IS
    l_target_empno   NUMBER;
    l_target_mobile  VARCHAR2(50);
    l_sender_name    VARCHAR2(100);
    l_company_name   sup_suppliers.company_name%TYPE;
    l_role_label     VARCHAR2(30);
    l_message        VARCHAR2(500);
    l_result         VARCHAR2(200);
BEGIN
    --------------------------------------------------
    -- 1️⃣ Supplier Name
    --------------------------------------------------
    SELECT company_name
      INTO l_company_name
      FROM sup_suppliers
     WHERE supplier_id = p_supplier_id;

    --------------------------------------------------
    -- 2️⃣ Sender Name
    --------------------------------------------------
    SELECT employee_name
      INTO l_sender_name
      FROM SUP_APPROVAL_MEMBERS
     WHERE employee_num = p_sender_empno;

    --------------------------------------------------
    -- 3️⃣ Determine TARGET EMPLOYEE
    --------------------------------------------------
    IF p_action = 'SUBMIT-APPROVAL' THEN
        SELECT
            CASE p_current_role
                WHEN 'PROC' THEN technical_empno
                WHEN 'TECH' THEN financial_by
                WHEN 'FIN'  THEN legal_by
                ELSE NULL
            END
        INTO l_target_empno
        FROM sup_supplier_approvals
        WHERE supplier_id = p_supplier_id;

        -- LEGAL approve → no next SMS
        IF p_current_role = 'LEGAL' THEN
            RETURN 'FINAL_APPROVAL_NO_SMS';
        END IF;

    ELSE
        -- REJECT → back to PROC
        SELECT procurement_by
          INTO l_target_empno
          FROM sup_supplier_approvals
         WHERE supplier_id = p_supplier_id;
    END IF;

    IF l_target_empno IS NULL THEN
        RETURN 'NO_TARGET_EMP';
    END IF;

    --------------------------------------------------
    -- 4️⃣ Get Target Mobile
    --------------------------------------------------
    SELECT c.mobile
      INTO l_target_mobile
      FROM central.emp_contact c
     WHERE c.emp_id = l_target_empno
       AND c.mobile_confirmed = 1
       AND c.mobile IS NOT NULL;

    --------------------------------------------------
    -- 5️⃣ Role Label for Sender
    --------------------------------------------------
    l_role_label :=
        CASE p_current_role
            WHEN 'PROC'  THEN 'Procurement'
            WHEN 'TECH'  THEN 'Technical'
            WHEN 'FIN'   THEN 'Finance'
            WHEN 'LEGAL' THEN 'Legal'
        END;

    --------------------------------------------------
    -- 6️⃣ Build Message
    --------------------------------------------------
    IF p_action = 'SUBMIT-REJECT' THEN
        l_message := 'Supplier "' || l_company_name ||
                     '" has been rejected by ' || l_sender_name ||
                     ' (' || l_role_label || ').';
    ELSE
        l_message := 'Supplier "' || l_company_name ||
                     '" is waiting for your approval.';
    END IF;

    --------------------------------------------------
    -- 7️⃣ Send SMS
    --------------------------------------------------
    l_result := central.sms_pkg.send_single(
                    l_message,
                    l_target_mobile
                );

    RETURN 'SMS_SENT_OK';

EXCEPTION
    WHEN NO_DATA_FOUND THEN
        RETURN 'NO_DATA_FOUND';
    WHEN OTHERS THEN
        apex_debug.error(
            'SMS ERROR supplier=' || p_supplier_id || ' : ' || SQLERRM
        );
        RETURN 'ERROR';
END;
/
