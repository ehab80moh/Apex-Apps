
  CREATE OR REPLACE EDITIONABLE TRIGGER "EPROMHQ"."BI_REQ_REQUEST_TYPES"
  before insert on "REQ_REQUEST_TYPES"
  for each row
begin
  if :NEW."ID" is null then
    select "REQ_REQUEST_TYPES_SEQ".nextval into :NEW."ID" from sys.dual;
  end if;
end;


/
ALTER TRIGGER "EPROMHQ"."BI_REQ_REQUEST_TYPES" ENABLE;
