
  CREATE OR REPLACE EDITIONABLE TRIGGER "EPROMHQ"."INV_MR_FOLLOW_UP_AUDIT_TRG"
BEFORE INSERT OR UPDATE OR DELETE ON EPROMHQ.INV_MR_FOLLOW_UP
FOR EACH ROW
DECLARE
    v_operation VARCHAR2(10);
    v_old_data VARCHAR2(4000);
    v_new_data VARCHAR2(4000);
BEGIN
    -- Determine the operation (Insert, Update, Delete)
    IF DELETING THEN
        v_operation := 'Delete';
    ELSIF INSERTING THEN
        v_operation := 'Insert';
    ELSIF UPDATING THEN
        v_operation := 'Update';
    END IF;

    -- Initialize old and new data strings
    v_old_data := NULL;
    v_new_data := NULL;

    -- For deletion or updating, construct the old_data string
    IF DELETING OR UPDATING THEN
        v_old_data :=
            NVL(TO_CHAR(:old.ID), 'NULL')||'-'||
            NVL(:old.PROJECT, 'NULL')||'-'||
            NVL(:old.PO_DESCRIPTION, 'NULL')||'-'||
            NVL(:old.PREPARED_BY, 'NULL')||'-'||
            NVL(TO_CHAR(:old.ISSUE_DATE), 'NULL')||'-'||
            NVL(:old.QTY, 'NULL')||'-'||
            NVL(:old.REMARKS, 'NULL')||'-'||
            NVL(:old.PURCHASE_ORDER_PO, 'NULL')||'-'||
            NVL(TO_CHAR(:old.MR_REGISTRATION_DATE), 'NULL')||'-'||
            NVL(:old.MR_CONDITION, 'NULL')||'-'||
            NVL(TO_CHAR(:old.DELIVERY_DATE), 'NULL')||'-'||
            NVL(:old.BUDGET_LE, 'NULL')||'-'||
            NVL(:old.BUDGET_DOLLARS, 'NULL')||'-'||
            NVL(:old.SUPPLIER, 'NULL');
    END IF;

    -- For insertion or updating, construct the new_data string
    IF INSERTING OR UPDATING THEN
        v_new_data :=
            NVL(TO_CHAR(:new.ID), 'NULL')||'-'||
            NVL(:new.PROJECT, 'NULL')||'-'||
            NVL(:new.PO_DESCRIPTION, 'NULL')||'-'||
            NVL(:new.PREPARED_BY, 'NULL')||'-'||
            NVL(TO_CHAR(:new.ISSUE_DATE), 'NULL')||'-'||
            NVL(:new.QTY, 'NULL')||'-'||
            NVL(:new.REMARKS, 'NULL')||'-'||
            NVL(:new.PURCHASE_ORDER_PO, 'NULL')||'-'||
            NVL(TO_CHAR(:new.MR_REGISTRATION_DATE), 'NULL')||'-'||
            NVL(:new.MR_CONDITION, 'NULL')||'-'||
            NVL(TO_CHAR(:new.DELIVERY_DATE), 'NULL')||'-'||
            NVL(:new.BUDGET_LE, 'NULL')||'-'||
            NVL(:new.BUDGET_DOLLARS, 'NULL')||'-'||
            NVL(:new.SUPPLIER, 'NULL');
    END IF;

    -- Insert into the audit table
    INSERT INTO EPROMHQ.INV_MR_FOLLOW_UP_AUDIT
        (AUDIT_DATE, APP_USER, OPERATION, OLD_DATA, NEW_DATA)
    VALUES
        (SYSDATE, COALESCE(SYS_CONTEXT('APEX$SESSION', 'APP_USER'), USER), v_operation, v_old_data, v_new_data);
END;
/
ALTER TRIGGER "EPROMHQ"."INV_MR_FOLLOW_UP_AUDIT_TRG" ENABLE;
