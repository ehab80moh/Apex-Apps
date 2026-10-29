
  CREATE OR REPLACE EDITIONABLE TRIGGER "EPROMHQ"."BI_HRF_EMERGENCY_CONTACT"
  before insert on "HRF_EMERGENCY_CONTACT"
  for each row
begin
  if :NEW."ID" is null then
    select "HRF_EMERGENCY_CONTACT_SEQ".nextval into :NEW."ID" from sys.dual;
  end if;
end;

/
ALTER TRIGGER "EPROMHQ"."BI_HRF_EMERGENCY_CONTACT" ENABLE;
