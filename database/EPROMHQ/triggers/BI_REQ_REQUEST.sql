
  CREATE OR REPLACE EDITIONABLE TRIGGER "EPROMHQ"."BI_REQ_REQUEST"
  before insert on "REQ_REQUESTS"
  for each row
begin
  if :NEW."REQUEST_ID" is null then
    select "REQ_REQUEST_SEQ".nextval into :NEW."REQUEST_ID" from sys.dual;
  end if;
end;



/
ALTER TRIGGER "EPROMHQ"."BI_REQ_REQUEST" ENABLE;
