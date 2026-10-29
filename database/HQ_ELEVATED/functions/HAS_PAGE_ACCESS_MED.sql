
  CREATE OR REPLACE EDITIONABLE FUNCTION "HQ_ELEVATED"."HAS_PAGE_ACCESS_MED" (
    p_user_id IN VARCHAR2
) RETURN BOOLEAN
IS
    l_dummy NUMBER;
BEGIN
    IF CENTRAL.IS_DEV_OR_SUPER_N(p_user_id) = 1 THEN
        RETURN TRUE;
    END IF;

    IF REGEXP_LIKE(p_user_id, '^\d+$') THEN
        BEGIN
            SELECT 1
              INTO l_dummy
              FROM MED.USERS
             WHERE EMP_ID = p_user_id
             AND ACTIVE = 1;

            RETURN TRUE;

        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                RETURN FALSE;
        END;
    END IF;

    RETURN FALSE;
END has_page_access_med;
/
