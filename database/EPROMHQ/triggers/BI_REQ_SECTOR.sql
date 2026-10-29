
  CREATE OR REPLACE EDITIONABLE TRIGGER "EPROMHQ"."BI_REQ_SECTOR"
  before insert on "REQ_SECTOR"
  for each row
begin
  if :NEW."SECTOR_ID" is null then
    select "REQ_SECTOR_SEQ".nextval into :NEW."SECTOR_ID" from sys.dual;
  end if;
end;



/
ALTER TRIGGER "EPROMHQ"."BI_REQ_SECTOR" ENABLE;
