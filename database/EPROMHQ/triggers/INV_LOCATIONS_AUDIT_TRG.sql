
  CREATE OR REPLACE EDITIONABLE TRIGGER "EPROMHQ"."INV_LOCATIONS_AUDIT_TRG"
BEFORE INSERT OR UPDATE OR DELETE ON INV_LOCATIONS
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
            NVL(TO_CHAR(:old.LOCATION_ID), 'NULL')||'-'||
            NVL(:old.LOCATION_NAME, 'NULL')||'-'||
            NVL(TO_CHAR(:old.CREATED_AT), 'NULL')||'-'||
            NVL(TO_CHAR(:old.UPDATED_AT), 'NULL')||'-'||
            NVL(:old.FINANCEL_LOCATION, 'NULL');
    END IF;

    -- For insertion or updating, construct the new_data string
    IF INSERTING OR UPDATING THEN
        v_new_data :=
            NVL(TO_CHAR(:new.LOCATION_ID), 'NULL')||'-'||
            NVL(:new.LOCATION_NAME, 'NULL')||'-'||
            NVL(TO_CHAR(:new.CREATED_AT), 'NULL')||'-'||
            NVL(TO_CHAR(:new.UPDATED_AT), 'NULL')||'-'||
            NVL(:new.FINANCEL_LOCATION, 'NULL');
    END IF;

    -- Insert into the audit table
    INSERT INTO INV_LOCATIONS_AUDIT
        (AUDIT_DATE, APP_USER, OPERATION, OLD_DATA, NEW_DATA)
    VALUES
        (SYSDATE, COALESCE(SYS_CONTEXT('APEX$SESSION', 'APP_USER'), USER), v_operation, v_old_data, v_new_data);

END;
/
ALTER TRIGGER "EPROMHQ"."INV_LOCATIONS_AUDIT_TRG" ENABLE;
