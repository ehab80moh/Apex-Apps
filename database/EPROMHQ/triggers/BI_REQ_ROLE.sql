
  CREATE OR REPLACE EDITIONABLE TRIGGER "EPROMHQ"."BI_REQ_ROLE"
  before insert on "REQ_ROLE"
  for each row
begin
  if :NEW."ROLE_ID" is null then
    select "REQ_ROLE_SEQ".nextval into :NEW."ROLE_ID" from sys.dual;
  end if;
end;



/
ALTER TRIGGER "EPROMHQ"."BI_REQ_ROLE" ENABLE;
