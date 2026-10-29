
  CREATE OR REPLACE EDITIONABLE TRIGGER "EPROMHQ"."BI_REQ_USER"
  before insert on "REQ_USERS"
  for each row
begin
  if :NEW."USER_ID" is null then
    select "REQ_USER_SEQ2".nextval into :NEW."USER_ID" from sys.dual;
  end if;

  -- Make sure to save the username in upper case
  :new.user_name := upper(:new.user_name);
  -- Hash the password so we are not saving clear text
  :new.password := req_hash_password(upper(:new.user_name), :new.password);

end;


/
ALTER TRIGGER "EPROMHQ"."BI_REQ_USER" ENABLE;
