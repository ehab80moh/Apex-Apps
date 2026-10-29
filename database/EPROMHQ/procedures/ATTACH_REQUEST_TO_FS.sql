
  CREATE OR REPLACE EDITIONABLE PROCEDURE "EPROMHQ"."ATTACH_REQUEST_TO_FS" AS

    CURSOR CR IS
    SELECT
        *
    FROM
        HRF_PERSON_ATTACHMENTS_REQUEST
    WHERE
        ACCEPTED = 1;

    FILE_NAME1    VARCHAR2(99);
    FILE_NAME2    VARCHAR2(99);
    FILE_NAME3    VARCHAR2(99);
    FILE_NAME4    VARCHAR2(99);
    RECORD_EXSIST NUMBER := 0;
BEGIN
    FOR C IN CR LOOP
        FILE_NAME1 := NULL;
        FILE_NAME2 := NULL;
        FILE_NAME3 := NULL;
        FILE_NAME4 := NULL;
        RECORD_EXSIST := 0;
--suggested file_naming {emp_id}-{person_id}-{random_num}-attach1 /
--{emp_id}-{person_id}-{random_num}-attach2
        IF C.ATTACH1 IS NOT NULL THEN
            FILE_NAME1 := C.EMP_ID
                          || '-'
                          || C.PERSON_ID
                          || '-'
                          || C.REQUEST_ID
                          || '-attach1.jpg';

            CENTRAL.BLOB_TO_FILE(P_BLOB => C.ATTACH1, P_DIR => 'ATTACH', P_FILENAME => FILE_NAME1);

        END IF;

        IF C.ATTACH2 IS NOT NULL THEN
            FILE_NAME2 := C.EMP_ID
                          || '-'
                          || C.PERSON_ID
                          || '-'
                          || C.REQUEST_ID
                          || '-attach2.jpg';

            CENTRAL.BLOB_TO_FILE(P_BLOB => C.ATTACH2, P_DIR => 'ATTACH', P_FILENAME => FILE_NAME2);

        END IF;

        IF C.ATTACH3 IS NOT NULL THEN
            FILE_NAME3 := C.EMP_ID
                          || '-'
                          || C.PERSON_ID
                          || '-'
                          || C.REQUEST_ID
                          || '-attach3.jpg';

            CENTRAL.BLOB_TO_FILE(P_BLOB => C.ATTACH3, P_DIR => 'ATTACH', P_FILENAME => FILE_NAME3);

        END IF;

        IF C.ATTACH4 IS NOT NULL THEN
            FILE_NAME4 := C.EMP_ID
                          || '-'
                          || C.PERSON_ID
                          || '-'
                          || C.REQUEST_ID
                          || '-attach4.jpg';

            CENTRAL.BLOB_TO_FILE(P_BLOB => C.ATTACH4, P_DIR => 'ATTACH', P_FILENAME => FILE_NAME4);

        END IF;

        SELECT
            COUNT(*)
        INTO RECORD_EXSIST
        FROM
            HRF_PERSON_ATTACHMENTS
        WHERE
                EMP_ID = C.EMP_ID
            AND PERSON_ID = C.PERSON_ID;

--delete old record if attachments exists for same person[already backed up on apps]
        IF ( RECORD_EXSIST > 0 ) THEN
            DELETE FROM HRF_PERSON_ATTACHMENTS
            WHERE
                    EMP_ID = C.EMP_ID
                AND PERSON_ID = C.PERSON_ID;

        END IF;

        INSERT INTO HRF_PERSON_ATTACHMENTS (
            ATTACH_ID,
            EMP_ID,
            PERSON_ID,
            ATTACH1,
            ATTACH2,
            ATTACH3,
            ATTACH4
        ) VALUES (
            C.REQUEST_ID,
            C.EMP_ID,
            C.PERSON_ID,
            FILE_NAME1,
            FILE_NAME2,
            FILE_NAME3,
            FILE_NAME4
        );


--set request = uploaded
update HRF_PERSON_ATTACHMENTS_REQUEST set ACCEPTED = 3
where REQUEST_ID = c.REQUEST_ID  ;

    END LOOP;

  --delete uploaded requests and rejected
    DELETE FROM HRF_PERSON_ATTACHMENTS_REQUEST
    WHERE
        ACCEPTED IN ( 3, 2 );
--  and request_date < sysdate -7; -- delete every week
    COMMIT;
END ATTACH_REQUEST_TO_FS;
/
