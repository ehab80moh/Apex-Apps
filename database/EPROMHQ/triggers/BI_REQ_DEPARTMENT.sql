
  CREATE OR REPLACE EDITIONABLE TRIGGER "EPROMHQ"."BI_REQ_DEPARTMENT"
  before insert on "REQ_DEPARTMENT"
  for each row
begin
  if :NEW."DEPARTMENT_ID" is null then
    select "REQ_DEPARTMENT_SEQ".nextval into :NEW."DEPARTMENT_ID" from sys.dual;
  end if;
end;



/
ALTER TRIGGER "EPROMHQ"."BI_REQ_DEPARTMENT" ENABLE;
