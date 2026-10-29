
  CREATE OR REPLACE EDITIONABLE TRIGGER "EPROMHQ"."BI_REQ_EMPLOYEE"
  before insert on "REQ_EMPLOYEE"
  for each row
begin
  if :NEW."ID" is null then
    select "REQ_EMPLOYEE_SEQ1".nextval into :NEW."ID" from sys.dual;
  end if;
end;



/
ALTER TRIGGER "EPROMHQ"."BI_REQ_EMPLOYEE" ENABLE;
