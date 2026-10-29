
  CREATE OR REPLACE EDITIONABLE FUNCTION "EPROMHQ"."INV_AUTH_USER" (
    p_username IN VARCHAR2,
    p_password IN VARCHAR2
) RETURN BOOLEAN AS
    l_user  VARCHAR2(40);
    l_pass  VARCHAR2(99);
    l_count NUMBER;
BEGIN
    IF p_password IS NOT NULL
       AND REGEXP_LIKE(p_password, '^[[:xdigit:]]{64}$')
       AND inv_2fa_pkg.validate_login_ticket(
               p_username   => p_username,
               p_ticket     => p_password,
               p_session_id => V('APP_SESSION')
           ) THEN
        apex_util.set_authentication_result(0);
        RETURN TRUE;
    END IF;

    SELECT COUNT(*)
      INTO l_count
      FROM inv_users
     WHERE UPPER(username) = UPPER(p_username);

    IF l_count > 0 THEN
        SELECT username, password
          INTO l_user, l_pass
          FROM inv_users
         WHERE UPPER(username) = UPPER(p_username);

        IF l_pass = md5(p_password) THEN
            apex_util.set_authentication_result(0);
            RETURN TRUE;
        ELSE
            apex_util.set_authentication_result(4);
            RETURN FALSE;
        END IF;
    ELSE
        apex_util.set_authentication_result(1);
        RETURN FALSE;
    END IF;

    apex_util.set_authentication_result(7);
    RETURN FALSE;
EXCEPTION
    WHEN OTHERS THEN
        apex_util.set_authentication_result(7);
        apex_util.set_custom_auth_status(SQLERRM);
        RETURN FALSE;
END inv_auth_user;
/
