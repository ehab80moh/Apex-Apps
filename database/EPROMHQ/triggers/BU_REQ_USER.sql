
  CREATE OR REPLACE EDITIONABLE TRIGGER "EPROMHQ"."BU_REQ_USER"
  before update on "REQ_USERS"
  for each row
begin

  -- Make sure to save the user name in upper case
  :new.user_name := upper(:new.user_name);
  -- If the new password is not null
  if :new.password is not null then
    -- Make sure to hash the password so it is not stored in clear text
    :new.password := req_hash_password(upper(:new.user_name), :new.password);
  -- If the password is empty
  else
    -- Keep the old hashed password. We don't want a blank password.
    :new.password := :old.password;
  end if;

end;


/
ALTER TRIGGER "EPROMHQ"."BU_REQ_USER" ENABLE;
