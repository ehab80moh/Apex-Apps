
  CREATE OR REPLACE EDITIONABLE PROCEDURE "HQ_ELEVATED"."REFRESH_XXSECRET_EMP_DATA" AS
    V_CNT NUMBER;
BEGIN
    -- Start a new transaction
    SAVEPOINT START_POINT;
    BEGIN
        -- Delete existing data
        DELETE FROM XXSECRET_EMP_CAREER_PROGRESS;

        DELETE FROM XXSECRET_EMP_PREV_EMPLOYERS;

        DELETE FROM XXSECRET_EMP_QUALIFICATIONS;

        DELETE FROM XXSECRET_EMP_RELATIVES;

        DELETE FROM XXSECRET_MAIN_EMP_DATA;

        -- Insert fresh data
        INSERT INTO XXSECRET_EMP_CAREER_PROGRESS
            SELECT
                *
            FROM
                APPS.XXSECRET_EMP_CAREER_PROGRESS@PROD;

        V_CNT := SQL%ROWCOUNT;
        DBMS_OUTPUT.PUT_LINE('Inserted ' || V_CNT
                             || ' rows into XXSECRET_EMP_CAREER_PROGRESS');
        INSERT INTO XXSECRET_EMP_PREV_EMPLOYERS
            SELECT
                *
            FROM
                APPS.XXSECRET_EMP_PREV_EMPLOYERS@PROD;

        V_CNT := SQL%ROWCOUNT;
        DBMS_OUTPUT.PUT_LINE('Inserted ' || V_CNT
                             || ' rows into XXSECRET_EMP_PREV_EMPLOYERS');
        INSERT INTO XXSECRET_EMP_QUALIFICATIONS
            SELECT
                *
            FROM
                APPS.XXSECRET_EMP_QUALIFICATIONS@PROD;

        V_CNT := SQL%ROWCOUNT;
        DBMS_OUTPUT.PUT_LINE('Inserted ' || V_CNT
                             || ' rows into XXSECRET_EMP_QUALIFICATIONS');
        INSERT INTO XXSECRET_EMP_RELATIVES
            SELECT
                *
            FROM
                APPS.XXSECRET_EMP_RELATIVES@PROD;

        V_CNT := SQL%ROWCOUNT;
        DBMS_OUTPUT.PUT_LINE('Inserted ' || V_CNT
                             || ' rows into XXSECRET_EMP_RELATIVES');
        INSERT INTO XXSECRET_MAIN_EMP_DATA
            SELECT
                *
            FROM
                APPS.XXSECRET_MAIN_EMP_DATA@PROD;

        V_CNT := SQL%ROWCOUNT;
        DBMS_OUTPUT.PUT_LINE('Inserted ' || V_CNT
                             || ' rows into XXSECRET_MAIN_EMP_DATA');
        INSERT INTO XXSECRET_UNPAID_ABSENCE
            SELECT
                *
            FROM
                APPS.XXSECRET_UNPAID_ABSENCE@PROD;

        V_CNT := SQL%ROWCOUNT;
        DBMS_OUTPUT.PUT_LINE('Inserted ' || V_CNT
                             || ' rows into xxsecret_Unpaid_absence');

        -- Commit the transaction if all inserts are successful
        COMMIT;
    EXCEPTION
        WHEN OTHERS THEN
            -- Rollback to the savepoint if any insert fails
            ROLLBACK TO START_POINT;
            RAISE;
    END;

END REFRESH_XXSECRET_EMP_DATA;
/
