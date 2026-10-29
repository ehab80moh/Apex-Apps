
  CREATE OR REPLACE EDITIONABLE TRIGGER "EPROMHQ"."INV_USERS_AUDIT_TRG"
BEFORE INSERT OR UPDATE OR DELETE ON EPROMHQ.INV_USERS
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
            NVL(TO_CHAR(:OLD.USER_ID), 'NULL') || '-' ||
            NVL(:OLD.USERNAME, 'NULL') || '-' ||
            NVL(:OLD.DEPARTMENT_ID, 'NULL') || '-' ||
            NVL(:OLD.ROLE, 'NULL');
    END IF;

    IF INSERTING OR UPDATING THEN
        v_new_data :=
            NVL(TO_CHAR(:NEW.USER_ID), 'NULL') || '-' ||
            NVL(:NEW.USERNAME, 'NULL') || '-' ||
            NVL(:NEW.DEPARTMENT_ID, 'NULL') || '-' ||
            NVL(:NEW.ROLE, 'NULL');
    END IF;

    INSERT INTO EPROMHQ.INV_USERS_AUDIT
        (AUDIT_DATE, APP_USER, OPERATION, OLD_DATA, NEW_DATA)
    VALUES
        (SYSDATE, COALESCE(SYS_CONTEXT('APEX$SESSION', 'APP_USER'), USER), v_operation, v_old_data, v_new_data);
END;
/
ALTER TRIGGER "EPROMHQ"."INV_USERS_AUDIT_TRG" ENABLE;
