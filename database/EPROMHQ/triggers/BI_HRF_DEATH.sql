
  CREATE OR REPLACE EDITIONABLE TRIGGER "EPROMHQ"."BI_HRF_DEATH"
  before insert on "HRF_DEATH"
  for each row
begin
  if :NEW."SERIAL" is null then
    select "HRF_DEATH_SEQ".nextval into :NEW."SERIAL" from sys.dual;
  end if;
end;

/
ALTER TRIGGER "EPROMHQ"."BI_HRF_DEATH" ENABLE;
