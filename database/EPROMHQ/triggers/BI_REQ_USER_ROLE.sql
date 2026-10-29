
  CREATE OR REPLACE EDITIONABLE TRIGGER "EPROMHQ"."BI_REQ_USER_ROLE"
  before insert on "REQ_USER_ROLE"
  for each row
begin
  if :NEW."USER_ROLE_ID" is null then
    select "REQ_USER_ROLE_SEQ".nextval into :NEW."USER_ROLE_ID" from sys.dual;
  end if;
end;



/
ALTER TRIGGER "EPROMHQ"."BI_REQ_USER_ROLE" ENABLE;
