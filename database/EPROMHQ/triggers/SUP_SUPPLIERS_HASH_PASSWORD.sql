
  CREATE OR REPLACE EDITIONABLE TRIGGER "EPROMHQ"."SUP_SUPPLIERS_HASH_PASSWORD"
before insert or update of password_hash on sup_suppliers
for each row
declare
  l_hash raw(32);
begin
  -- Only hash when password is provided
  if :new.password_hash is not null then
    -- If it's plain text (not already a 64-char hex string)
    if length(:new.password_hash) < 64 then
      l_hash := dbms_crypto.hash(
                  utl_raw.cast_to_raw(:new.password_hash),
                  dbms_crypto.hash_sh256);
      :new.password_hash := rawtohex(l_hash);
    end if;
  else
    -- If null on update, retain old hash
    if updating then
      :new.password_hash := :old.password_hash;
    end if;
  end if;
end;

/
ALTER TRIGGER "EPROMHQ"."SUP_SUPPLIERS_HASH_PASSWORD" ENABLE;
