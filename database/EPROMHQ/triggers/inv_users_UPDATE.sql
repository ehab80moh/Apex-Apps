
  CREATE OR REPLACE EDITIONABLE TRIGGER "EPROMHQ"."inv_users_UPDATE"
  before update on inv_users
  for each row
  declare
  l_new_pass_hashed varchar(99);
begin
l_new_pass_hashed  := md5( :new.PASSWORD);
  -- If the new PASS is not null
  if :new.PASSWORD is not null  and :old.PASSWORD <> :new.PASSWORD  and l_new_pass_hashed <> :old.PASSWORD then
    -- Make sure to hash the PASS so it is not stored in clear text
    :new.PASSWORD := l_new_pass_hashed;


  -- If the PASS is empty
  else
    -- Keep the old hashed PASS. We don't want a blank PASS.
    :new.PASSWORD := :old.PASSWORD;
  end if;
end;
/
ALTER TRIGGER "EPROMHQ"."inv_users_UPDATE" ENABLE;
