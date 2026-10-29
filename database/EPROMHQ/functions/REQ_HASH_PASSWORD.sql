
  CREATE OR REPLACE EDITIONABLE FUNCTION "EPROMHQ"."REQ_HASH_PASSWORD"
  (p_user_name in varchar2,
   p_password  in varchar2)
return varchar2
is
  l_password varchar2(255);
  -- The following salt is an example.
  -- Should probably be changed to another random string.
  l_salt  varchar2(255) := '2345USFGOJN2T3HW89EFGOBN23R5SDFGAKL';
begin
    --
    -- The following encryptes the password using a salt string and the
    -- DBMS_OBFUSCATION_TOOLKIT.
    -- This is a one-way encryption using MD5
    l_password :=    dbms_crypto.hash(utl_raw.cast_to_raw(p_password), 2);
    return l_password;
end;
/
