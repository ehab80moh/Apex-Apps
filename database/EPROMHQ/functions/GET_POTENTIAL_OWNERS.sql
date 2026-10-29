
  CREATE OR REPLACE EDITIONABLE FUNCTION "EPROMHQ"."GET_POTENTIAL_OWNERS" (
    p_task_id IN NUMBER,
    p_separator IN VARCHAR2 DEFAULT ','
) RETURN VARCHAR2 IS
    v_participants VARCHAR2(32767);
    v_participant VARCHAR2(255);
    v_cursor SYS_REFCURSOR;
BEGIN
    OPEN v_cursor FOR
        SELECT participant
        FROM apex_task_participants
        WHERE PARTICIPANT_TYPE = 'POTENTIAL_OWNER'
        AND task_id = p_task_id
        ORDER BY participant;

    LOOP
        FETCH v_cursor INTO v_participant;
        EXIT WHEN v_cursor%NOTFOUND;
        IF v_participants IS NOT NULL THEN
            v_participants := v_participants || p_separator;
        END IF;
        v_participants := v_participants || v_participant;
    END LOOP;

    CLOSE v_cursor;

    RETURN v_participants;
END;
/
