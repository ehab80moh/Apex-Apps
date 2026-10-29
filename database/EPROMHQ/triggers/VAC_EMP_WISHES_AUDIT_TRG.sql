
  CREATE OR REPLACE EDITIONABLE TRIGGER "EPROMHQ"."VAC_EMP_WISHES_AUDIT_TRG"
BEFORE INSERT OR UPDATE OR DELETE ON EPROMHQ.VAC_EMP_WISHES
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
        v_old_data := NVL(TO_CHAR(:OLD.WISH_ID), 'NULL') || '-' ||
                      NVL(TO_CHAR(:OLD.EMP_ID), 'NULL') || '-' ||
                      NVL(TO_CHAR(:OLD.BLOC_ID), 'NULL') || '-' ||
                      NVL(TO_CHAR(:OLD.TRIP_ID), 'NULL') || '-' ||
                      NVL(TO_CHAR(:OLD.ORD), 'NULL');
    END IF;

    IF INSERTING OR UPDATING THEN
        v_new_data := NVL(TO_CHAR(:NEW.WISH_ID), 'NULL') || '-' ||
                      NVL(TO_CHAR(:NEW.EMP_ID), 'NULL') || '-' ||
                      NVL(TO_CHAR(:NEW.BLOC_ID), 'NULL') || '-' ||
                      NVL(TO_CHAR(:NEW.TRIP_ID), 'NULL') || '-' ||
                      NVL(TO_CHAR(:NEW.ORD), 'NULL');
    END IF;

    INSERT INTO EPROMHQ.VAC_EMP_WISHES_AUDIT
        (AUDIT_DATE, APP_USER, OPERATION, OLD_DATA, NEW_DATA)
    VALUES
        (SYSDATE, COALESCE(SYS_CONTEXT('APEX$SESSION', 'APP_USER'), USER), v_operation, v_old_data, v_new_data);
END;

/
ALTER TRIGGER "EPROMHQ"."VAC_EMP_WISHES_AUDIT_TRG" ENABLE;
