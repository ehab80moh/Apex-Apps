
  CREATE OR REPLACE EDITIONABLE TRIGGER "EPROMHQ"."BI_REQ_REQUEST_FLOW"
  before insert or update on "REQ_REQUEST_FLOW"
   REFERENCING OLD AS OLD NEW AS NEW
  for each row
begin
  IF INSERTING THEN
      if :NEW."ID" is null
       then
        select "REQ_REQUEST_FLOW_SEQ".nextval into :NEW."ID" from sys.dual;
      end if;
         :NEW.CREATED_BY := NVL(v('APP_USER') ,USER);
         :NEW.CREATED_ON := SYSDATE;
    ELSIF UPDATING THEN
         :NEW.CREATED_BY := :OLD.CREATED_BY;
         :NEW.CREATED_ON := :OLD.CREATED_ON;
         :NEW.UPDATED_BY := NVL(v('APP_USER') ,USER);
         :NEW.UPDTAED_ON := SYSDATE;
    END IF;
end;
/
ALTER TRIGGER "EPROMHQ"."BI_REQ_REQUEST_FLOW" ENABLE;
