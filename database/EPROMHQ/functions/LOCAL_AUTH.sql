
  CREATE OR REPLACE EDITIONABLE FUNCTION "EPROMHQ"."LOCAL_AUTH" (
  p_username IN VARCHAR2,
  p_password IN VARCHAR2
) RETURN BOOLEAN
IS
  l_user_id       user_info.user_id%TYPE;
  l_pwd_hash_db   user_info.pwd_hash%TYPE;
  l_pwd_hash_in   NUMBER;
BEGIN
  -- Get user (by email or username)
  SELECT u.user_id, u.pwd_hash
    INTO l_user_id, l_pwd_hash_db
    FROM user_info u
   WHERE (LOWER(u.email)    = LOWER(TRIM(p_username))
       OR LOWER(u.username) = LOWER(TRIM(p_username)))
     AND u.status = 'ACTIVE'
     AND u.is_verified = 'YES';

  -- Hash password + salt (USER_ID) using DBMS_UTILITY
  -- base = 1, hash_size = 999999999 (range bucket)
  l_pwd_hash_in :=
    DBMS_UTILITY.GET_HASH_VALUE(
      name      => p_password || l_user_id,
      base      => 1,
      hash_size => 999999999
    );

  RETURN (TO_CHAR(l_pwd_hash_in) = l_pwd_hash_db);

EXCEPTION
  WHEN NO_DATA_FOUND THEN
    RETURN FALSE;
  WHEN OTHERS THEN
    RETURN FALSE;
END LOCAL_AUTH;
/
