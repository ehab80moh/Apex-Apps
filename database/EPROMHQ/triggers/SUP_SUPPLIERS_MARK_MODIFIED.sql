
  CREATE OR REPLACE EDITIONABLE TRIGGER "EPROMHQ"."SUP_SUPPLIERS_MARK_MODIFIED"
BEFORE UPDATE ON sup_suppliers
FOR EACH ROW
BEGIN
    IF :OLD.status LIKE '%APPROVED%'
       AND :OLD.is_new = 'N'
    THEN
        :NEW.status      := :OLD.status; -- protect status
        :NEW.is_modified := 'Y';
    END IF;
END;

/
ALTER TRIGGER "EPROMHQ"."SUP_SUPPLIERS_MARK_MODIFIED" ENABLE;
