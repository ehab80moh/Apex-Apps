
  CREATE OR REPLACE EDITIONABLE FUNCTION "EPROMHQ"."SUP_GET_WAITING_COUNT" (
    p_role IN VARCHAR2
) RETURN NUMBER
IS
    l_cnt NUMBER := 0;
BEGIN
    SELECT COUNT(*)
    INTO   l_cnt
    FROM   sup_suppliers
    WHERE
          (p_role = 'PROC'  AND status = 'COMPLETE')
       OR (p_role = 'TECH'  AND status = 'PROCUREMENT_APPROVED')
       OR (p_role = 'FIN'   AND status = 'TECHNICAL_APPROVED')
       OR (p_role = 'LEGAL' AND status = 'FINANCE_APPROVED');

    RETURN l_cnt;
END sup_get_waiting_count;
/
