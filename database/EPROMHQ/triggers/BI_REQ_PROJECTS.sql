
  CREATE OR REPLACE EDITIONABLE TRIGGER "EPROMHQ"."BI_REQ_PROJECTS"
  before insert on "REQ_PROJECTS"
  for each row
begin
  if :NEW."ID" is null then
    select "REQ_PROJECTS_SEQ".nextval into :NEW."ID" from sys.dual;
  end if;
end;


/
ALTER TRIGGER "EPROMHQ"."BI_REQ_PROJECTS" ENABLE;
