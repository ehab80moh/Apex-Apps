
  CREATE OR REPLACE EDITIONABLE PACKAGE BODY "EPROMHQ"."INV_2FA_PKG" AS
    c_challenge_minutes CONSTANT PLS_INTEGER := 5;
    c_ticket_minutes    CONSTANT PLS_INTEGER := 5;
    c_max_attempts      CONSTANT PLS_INTEGER := 5;
    c_max_sends         CONSTANT PLS_INTEGER := 3;

    FUNCTION hash_value(p_value IN VARCHAR2) RETURN VARCHAR2 IS
        l_hash VARCHAR2(64);
    BEGIN
        SELECT RAWTOHEX(STANDARD_HASH(p_value, 'SHA256'))
          INTO l_hash
          FROM dual;
        RETURN l_hash;
    END hash_value;

    PROCEDURE start_challenge(
        p_username     IN  VARCHAR2,
        p_session_id   IN  VARCHAR2,
        p_challenge_id OUT VARCHAR2,
        p_message      OUT VARCHAR2,
        p_success      OUT NUMBER
    ) IS
        l_username       inv_users.username%TYPE;
        l_employee       inv_users.employee_number%TYPE;
        l_registered_mobile inv_users.mobile_number%TYPE;
        l_mobile         VARCHAR2(100);
        l_mobile_clean   VARCHAR2(100);
        l_masked_mobile  VARCHAR2(32);
        l_otp            VARCHAR2(6);
        l_salt           VARCHAR2(64);
        l_challenge_id   VARCHAR2(64);
        l_otp_hash       VARCHAR2(64);
        l_recent_sends   PLS_INTEGER;
        l_sent           NUMBER;
        l_message        VARCHAR2(4000);
    BEGIN
        p_challenge_id := NULL;
        p_message := NULL;
        p_success := 0;

        IF p_session_id IS NULL THEN
            p_message := 'The authentication session is invalid. Please try again.';
            RETURN;
        END IF;

        BEGIN
            SELECT username, employee_number, mobile_number
              INTO l_username, l_employee, l_registered_mobile
              FROM inv_users
             WHERE UPPER(username) = UPPER(p_username);
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                p_message := 'Invalid Inventory credentials.';
                RETURN;
            WHEN TOO_MANY_ROWS THEN
                p_message := 'The Inventory account configuration is invalid.';
                RETURN;
        END;

        SELECT COUNT(*)
          INTO l_recent_sends
          FROM inv_2fa_challenges
         WHERE (
                   (l_employee IS NOT NULL AND employee_number = l_employee)
                OR (l_employee IS NULL AND UPPER(inventory_username) = UPPER(l_username))
               )
           AND created_at >= SYSTIMESTAMP - INTERVAL '10' MINUTE;

        IF l_recent_sends >= c_max_sends THEN
            p_message := 'Too many verification requests. Please wait and try again.';
            RETURN;
        END IF;

        IF l_employee IS NOT NULL THEN
            l_mobile := central.sms_pkg.get_emp_mobile(l_employee, 1);
        ELSE
            l_mobile := l_registered_mobile;
        END IF;

        IF l_mobile IS NULL THEN
            IF l_employee IS NULL THEN
                p_message := 'No mobile number is configured for this Inventory account.';
            ELSE
                p_message := 'No confirmed mobile number is configured for this employee.';
            END IF;
            RETURN;
        END IF;

        l_mobile_clean := REGEXP_REPLACE(l_mobile, '[^0-9]', '');
        IF LENGTH(l_mobile_clean) < 4 THEN
            p_message := 'The confirmed employee mobile number is configured but cannot be safely displayed.';
            RETURN;
        END IF;

        l_masked_mobile := SUBSTR(l_mobile_clean, 1, 2)
                        || '****'
                        || SUBSTR(l_mobile_clean, -2);

        l_challenge_id := RAWTOHEX(SYS_GUID());
        l_salt := RAWTOHEX(SYS_GUID());
        l_otp := TO_CHAR(TRUNC(DBMS_RANDOM.VALUE(0, 1000000)), 'FM000000');
        l_otp_hash := hash_value(l_challenge_id || ':' || l_otp || ':' || l_salt);

        INSERT INTO inv_2fa_challenges (
            challenge_id,
            apex_session_id,
            inventory_username,
            employee_number,
            otp_hash,
            otp_salt,
            expires_at
        ) VALUES (
            l_challenge_id,
            p_session_id,
            l_username,
            l_employee,
            l_otp_hash,
            l_salt,
            SYSTIMESTAMP + NUMTODSINTERVAL(c_challenge_minutes, 'MINUTE')
        );

        l_message := 'Inventory verification is: ' || l_otp
                  || '. It expires in "' || c_challenge_minutes || '" minutes.';
        l_sent := central.sms_pkg.send_single(msg => l_message, mobile => l_mobile);

        IF NVL(l_sent, 0) <> 1 THEN
            DELETE FROM inv_2fa_challenges
             WHERE challenge_id = l_challenge_id;
            COMMIT;
            p_message := 'The verification code could not be sent. Please try again.';
            RETURN;
        END IF;

        COMMIT;
        p_challenge_id := l_challenge_id;
        p_message := 'A verification code was sent to the registered mobile number ending in '
                  || l_masked_mobile || '.';
        p_success := 1;
    EXCEPTION
        WHEN OTHERS THEN
            ROLLBACK;
            p_challenge_id := NULL;
            p_message := 'The verification code could not be sent. Please try again.';
            p_success := 0;
    END start_challenge;

    PROCEDURE complete_challenge(
        p_challenge_id IN  VARCHAR2,
        p_otp          IN  VARCHAR2,
        p_session_id   IN  VARCHAR2,
        p_ticket       OUT VARCHAR2,
        p_message      OUT VARCHAR2,
        p_success      OUT NUMBER
    ) IS
        l_username     inv_2fa_challenges.inventory_username%TYPE;
        l_otp_hash     inv_2fa_challenges.otp_hash%TYPE;
        l_salt         inv_2fa_challenges.otp_salt%TYPE;
        l_expires_at   inv_2fa_challenges.expires_at%TYPE;
        l_attempts     inv_2fa_challenges.attempts%TYPE;
        l_expected     VARCHAR2(64);
        l_ticket       VARCHAR2(64);
        l_ticket_hash  VARCHAR2(64);
    BEGIN
        p_ticket := NULL;
        p_message := NULL;
        p_success := 0;

        IF p_challenge_id IS NULL OR p_otp IS NULL OR p_session_id IS NULL THEN
            p_message := 'Enter the verification code.';
            RETURN;
        END IF;

        BEGIN
            SELECT inventory_username, otp_hash, otp_salt, expires_at, attempts
              INTO l_username, l_otp_hash, l_salt, l_expires_at, l_attempts
              FROM inv_2fa_challenges
             WHERE challenge_id = p_challenge_id
               AND apex_session_id = p_session_id
               AND used_at IS NULL
               AND verified_at IS NULL
             FOR UPDATE;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                p_message := 'This verification request is invalid or already used.';
                RETURN;
        END;

        IF l_expires_at <= SYSTIMESTAMP THEN
            p_message := 'The verification code has expired. Request a new code.';
            RETURN;
        END IF;

        IF l_attempts >= c_max_attempts THEN
            p_message := 'Too many invalid attempts. Request a new code.';
            RETURN;
        END IF;

        l_expected := hash_value(p_challenge_id || ':' || TRIM(p_otp) || ':' || l_salt);
        IF l_expected <> l_otp_hash THEN
            UPDATE inv_2fa_challenges
               SET attempts = attempts + 1
             WHERE challenge_id = p_challenge_id;
            COMMIT;
            p_message := 'The verification code is incorrect.';
            RETURN;
        END IF;

        l_ticket := RAWTOHEX(SYS_GUID()) || RAWTOHEX(SYS_GUID());
        l_ticket_hash := hash_value(l_ticket || ':' || l_salt);
        UPDATE inv_2fa_challenges
           SET ticket_hash = l_ticket_hash,
               verified_at = SYSTIMESTAMP,
               expires_at = SYSTIMESTAMP + NUMTODSINTERVAL(c_ticket_minutes, 'MINUTE')
         WHERE challenge_id = p_challenge_id;

        COMMIT;
        p_ticket := l_ticket;
        p_message := 'Verification completed.';
        p_success := 1;
    EXCEPTION
        WHEN OTHERS THEN
            ROLLBACK;
            p_ticket := NULL;
            p_message := 'The verification code could not be checked. Please try again.';
            p_success := 0;
    END complete_challenge;

    FUNCTION validate_login_ticket(
        p_username   IN VARCHAR2,
        p_ticket     IN VARCHAR2,
        p_session_id IN VARCHAR2
    ) RETURN BOOLEAN IS
        l_challenge_id inv_2fa_challenges.challenge_id%TYPE;
        l_salt         inv_2fa_challenges.otp_salt%TYPE;
        l_ticket_hash  inv_2fa_challenges.ticket_hash%TYPE;
        l_expected_hash VARCHAR2(64);
    BEGIN
        IF p_username IS NULL OR p_ticket IS NULL OR p_session_id IS NULL THEN
            RETURN FALSE;
        END IF;

        SELECT challenge_id, otp_salt, ticket_hash
          INTO l_challenge_id, l_salt, l_ticket_hash
          FROM inv_2fa_challenges
         WHERE UPPER(inventory_username) = UPPER(p_username)
           AND apex_session_id = p_session_id
           AND verified_at IS NOT NULL
           AND used_at IS NULL
           AND expires_at > SYSTIMESTAMP
         FOR UPDATE;

        l_expected_hash := hash_value(p_ticket || ':' || l_salt);
        IF l_expected_hash <> l_ticket_hash THEN
            ROLLBACK;
            RETURN FALSE;
        END IF;

        UPDATE inv_2fa_challenges
           SET used_at = SYSTIMESTAMP
         WHERE challenge_id = l_challenge_id;
        COMMIT;
        RETURN TRUE;
    EXCEPTION
        WHEN OTHERS THEN
            ROLLBACK;
            RETURN FALSE;
    END validate_login_ticket;
END inv_2fa_pkg;
/
