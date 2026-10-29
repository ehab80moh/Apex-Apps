
  CREATE OR REPLACE EDITIONABLE TRIGGER "EPROMHQ"."INV_INVENTORIES_AUDIT_TRG"
BEFORE INSERT OR UPDATE OR DELETE ON INV_INVENTORIES
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
            'INV_ID=' || NVL(TO_CHAR(:old.INV_ID), 'NULL') || '|' ||
            'DEPARTMENT_ID=' || NVL(TO_CHAR(:old.DEPARTMENT_ID), 'NULL') || '|' ||
            'LOCATION_ID=' || NVL(TO_CHAR(:old.LOCATION_ID), 'NULL') || '|' ||
            'CATEGORY_ID=' || NVL(TO_CHAR(:old.CATEGORY_ID), 'NULL') || '|' ||
            'COMPANY_ID=' || NVL(TO_CHAR(:old.COMPANY_ID), 'NULL') || '|' ||
            'SERIAL=' || NVL(:old.SERIAL, 'NULL') || '|' ||
            'EMPLOYEE_NAME=' || NVL(:old.EMPLOYEE_NAME, 'NULL') || '|' ||
            'EMPLOYEE_ID=' || NVL(:old.EMPLOYEE_ID, 'NULL') || '|' ||
            'RECEIVED_DATE=' || NVL(TO_CHAR(:old.RECEIVED_DATE, 'DD-MM-YYYY'), 'NULL') || '|' ||
            'PERCENTAGE=' || NVL(TO_CHAR(:old.PERCENTAGE), 'NULL') || '|' ||
            'PO_DETAILS=' || NVL(:old.PO_DETAILS, 'NULL') || '|' ||
            'REMARKS=' || NVL(:old.REMARKS, 'NULL') || '|' ||
            'LAST_EXIST_DATE=' || NVL(TO_CHAR(:old.LAST_EXIST_DATE, 'DD-MM-YYYY'), 'NULL') || '|' ||
            'CREATED_AT=' || NVL(TO_CHAR(:old.CREATED_AT, 'DD-MM-YYYY HH24:MI:SS'), 'NULL') || '|' ||
            'UPDATED_AT=' || NVL(TO_CHAR(:old.UPDATED_AT, 'DD-MM-YYYY HH24:MI:SS'), 'NULL') || '|' ||
            'PLACEMENT_DETAILS=' || NVL(:old.PLACEMENT_DETAILS, 'NULL') || '|' ||
            'MODEL_ID=' || NVL(TO_CHAR(:old.MODEL_ID), 'NULL') || '|' ||
            'EMPLOYEE_DEPARTMENT=' || NVL(TO_CHAR(:old.EMPLOYEE_DEPARTMENT), 'NULL') || '|' ||
            'UPDATED_BY=' || NVL(:old.UPDATED_BY, 'NULL') || '|' ||
            'CREATED_BY=' || NVL(:old.CREATED_BY, 'NULL') || '|' ||
            'FINANCE_LOCATION=' || NVL(:old.FINANCE_LOCATION, 'NULL') || '|' ||
            'FINANCE_ID=' || NVL(TO_CHAR(:old.FINANCE_ID), 'NULL');
    END IF;

    -- For insertion or updating, construct the new_data string
    IF INSERTING OR UPDATING THEN
        v_new_data :=
            'INV_ID=' || NVL(TO_CHAR(:new.INV_ID), 'NULL') || '|' ||
            'DEPARTMENT_ID=' || NVL(TO_CHAR(:new.DEPARTMENT_ID), 'NULL') || '|' ||
            'LOCATION_ID=' || NVL(TO_CHAR(:new.LOCATION_ID), 'NULL') || '|' ||
            'CATEGORY_ID=' || NVL(TO_CHAR(:new.CATEGORY_ID), 'NULL') || '|' ||
            'COMPANY_ID=' || NVL(TO_CHAR(:new.COMPANY_ID), 'NULL') || '|' ||
            'SERIAL=' || NVL(:new.SERIAL, 'NULL') || '|' ||
            'EMPLOYEE_NAME=' || NVL(:new.EMPLOYEE_NAME, 'NULL') || '|' ||
            'EMPLOYEE_ID=' || NVL(:new.EMPLOYEE_ID, 'NULL') || '|' ||
            'RECEIVED_DATE=' || NVL(TO_CHAR(:new.RECEIVED_DATE, 'DD-MM-YYYY'), 'NULL') || '|' ||
            'PERCENTAGE=' || NVL(TO_CHAR(:new.PERCENTAGE), 'NULL') || '|' ||
            'PO_DETAILS=' || NVL(:new.PO_DETAILS, 'NULL') || '|' ||
            'REMARKS=' || NVL(:new.REMARKS, 'NULL') || '|' ||
            'LAST_EXIST_DATE=' || NVL(TO_CHAR(:new.LAST_EXIST_DATE, 'DD-MM-YYYY'), 'NULL') || '|' ||
            'CREATED_AT=' || NVL(TO_CHAR(:new.CREATED_AT, 'DD-MM-YYYY HH24:MI:SS'), 'NULL') || '|' ||
            'UPDATED_AT=' || NVL(TO_CHAR(:new.UPDATED_AT, 'DD-MM-YYYY HH24:MI:SS'), 'NULL') || '|' ||
            'PLACEMENT_DETAILS=' || NVL(:new.PLACEMENT_DETAILS, 'NULL') || '|' ||
            'MODEL_ID=' || NVL(TO_CHAR(:new.MODEL_ID), 'NULL') || '|' ||
            'EMPLOYEE_DEPARTMENT=' || NVL(TO_CHAR(:new.EMPLOYEE_DEPARTMENT), 'NULL') || '|' ||
            'UPDATED_BY=' || NVL(:new.UPDATED_BY, 'NULL') || '|' ||
            'CREATED_BY=' || NVL(:new.CREATED_BY, 'NULL') || '|' ||
            'FINANCE_LOCATION=' || NVL(:new.FINANCE_LOCATION, 'NULL') || '|' ||
            'FINANCE_ID=' || NVL(TO_CHAR(:new.FINANCE_ID), 'NULL');
    END IF;

    -- Insert into the audit table
    INSERT INTO INV_INVENTORIES_AUDIT
        (AUDIT_DATE, APP_USER, OPERATION, OLD_DATA, NEW_DATA)
    VALUES
        (SYSDATE, COALESCE(SYS_CONTEXT('APEX$SESSION', 'APP_USER'), USER), v_operation, v_old_data, v_new_data);

EXCEPTION
    WHEN OTHERS THEN
    null;
        -- Log error without stopping the main transaction
--        INSERT INTO ERROR_LOG (ERROR_DATE, ERROR_MESSAGE, TRIGGER_NAME)
--        VALUES (SYSDATE, SQLERRM, 'INV_INVENTORIES_AUDIT_TRG');
END;
/
ALTER TRIGGER "EPROMHQ"."INV_INVENTORIES_AUDIT_TRG" ENABLE;
