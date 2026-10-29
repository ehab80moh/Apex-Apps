
  CREATE OR REPLACE EDITIONABLE TRIGGER "EPROMHQ"."BI_FILING2"
  before insert on "MEMO_FILLING"
  for each row
begin
  if :NEW."ID_FILLING2" is null then
    select "FILING2_SEQ".nextval into :NEW."ID_FILLING2" from sys.dual;
  end if;
end;


/
ALTER TRIGGER "EPROMHQ"."BI_FILING2" ENABLE;
