
  CREATE OR REPLACE EDITIONABLE TRIGGER "EPROMHQ"."INV_INK_DEDUCTED_AUDIT_TRG"
BEFORE INSERT OR UPDATE OR DELETE ON EPROMHQ.INV_INK_DEDUCTED
FOR EACH ROW
DECLARE
    v_operation VARCHAR2(10);
    v_old_data VARCHAR2(4000);
    v_new_data VARCHAR2(4000);
BEGIN
    IF DELETING THEN
        v_operation := 'Delete';
    ELSIF INSERTING THEN
        v_operation := 'Insert';
    ELSIF UPDATING THEN
        v_operation := 'Update';
    END IF;

    v_old_data := NULL;
    v_new_data := NULL;

    IF DELETING OR UPDATING THEN
        v_old_data :=
            NVL(TO_CHAR(:OLD.ISSUE_DATE), 'NULL') || '-' ||
            NVL(:OLD.PRINTER, 'NULL') || '-' ||
            NVL(:OLD.STOCK_STATUS, 'NULL') || '-' ||
            NVL(:OLD.OWNER, 'NULL') || '-' ||
            NVL(:OLD.DEPARTMENT, 'NULL') || '-' ||
            NVL(:OLD.REMARKS, 'NULL') || '-' ||
            NVL(TO_CHAR(:OLD.ID), 'NULL');
    END IF;

    IF INSERTING OR UPDATING THEN
        v_new_data :=
            NVL(TO_CHAR(:NEW.ISSUE_DATE), 'NULL') || '-' ||
            NVL(:NEW.PRINTER, 'NULL') || '-' ||
            NVL(:NEW.STOCK_STATUS, 'NULL') || '-' ||
            NVL(:NEW.OWNER, 'NULL') || '-' ||
            NVL(:NEW.DEPARTMENT, 'NULL') || '-' ||
            NVL(:NEW.REMARKS, 'NULL') || '-' ||
            NVL(TO_CHAR(:NEW.ID), 'NULL');
    END IF;

    INSERT INTO EPROMHQ.INV_INK_DEDUCTED_AUDIT
        (AUDIT_DATE, APP_USER, OPERATION, OLD_DATA, NEW_DATA)
    VALUES
        (SYSDATE, COALESCE(SYS_CONTEXT('APEX$SESSION', 'APP_USER'), USER), v_operation, v_old_data, v_new_data);
END;
/
ALTER TRIGGER "EPROMHQ"."INV_INK_DEDUCTED_AUDIT_TRG" ENABLE;
