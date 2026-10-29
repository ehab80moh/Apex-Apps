
  CREATE OR REPLACE EDITIONABLE FUNCTION "HQ_ELEVATED"."GET_CLOB_CONTENT" (
    p_clob     CLOB,
    p_length   NUMBER DEFAULT 4000,
    p_offset   NUMBER DEFAULT 1
) RETURN CLOB IS
    v_result CLOB;
BEGIN
    -- Ensure the input length does not exceed the CLOB size
    IF DBMS_LOB.GETLENGTH(p_clob) < p_length THEN
        v_result := DBMS_LOB.SUBSTR(p_clob, DBMS_LOB.GETLENGTH(p_clob), p_offset);
    ELSE
        v_result := DBMS_LOB.SUBSTR(p_clob, p_length, p_offset);
    END IF;

    RETURN v_result;
END;
/
