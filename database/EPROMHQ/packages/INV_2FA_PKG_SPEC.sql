
  CREATE OR REPLACE EDITIONABLE PACKAGE "EPROMHQ"."INV_2FA_PKG" AUTHID DEFINER AS
    PROCEDURE start_challenge(
        p_username     IN  VARCHAR2,
        p_session_id   IN  VARCHAR2,
        p_challenge_id OUT VARCHAR2,
        p_message      OUT VARCHAR2,
        p_success      OUT NUMBER
    );

    PROCEDURE complete_challenge(
        p_challenge_id IN  VARCHAR2,
        p_otp          IN  VARCHAR2,
        p_session_id   IN  VARCHAR2,
        p_ticket       OUT VARCHAR2,
        p_message      OUT VARCHAR2,
        p_success      OUT NUMBER
    );

    FUNCTION validate_login_ticket(
        p_username   IN VARCHAR2,
        p_ticket     IN VARCHAR2,
        p_session_id IN VARCHAR2
    ) RETURN BOOLEAN;
END inv_2fa_pkg;
/
