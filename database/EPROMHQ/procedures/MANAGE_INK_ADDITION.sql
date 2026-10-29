
  CREATE OR REPLACE EDITIONABLE PROCEDURE "EPROMHQ"."MANAGE_INK_ADDITION" (
    p_ink_model IN VARCHAR2,
    P_PRINTER_MODEL in varchar2,
    p_quantity IN NUMBER,
    p_operation IN VARCHAR2,  -- 'INSERT', 'UPDATE', 'DELETE'
    p_original_quantity IN NUMBER ,  -- Original quantity before update or delete, default is NULL
    p_DELETE_DEDUCTED in varchar2 DEFAULT NULL
)
IS
BEGIN
    IF p_operation = 'INSERT' THEN
        MERGE INTO EPROMHQ.INV_INK_LEVEL il
        USING (SELECT p_ink_model AS INK_MODEL, p_quantity AS QUANTITY FROM DUAL) i
        ON (il.INK_MODEL = i.INK_MODEL)
        WHEN MATCHED THEN
            UPDATE SET il.AVAILABLE_LEVEL = il.AVAILABLE_LEVEL + i.QUANTITY
        WHEN NOT MATCHED THEN
            INSERT (PRINTER_COUNT, PRINTER_MODEL, INK_MODEL, MAX_LEVEL, MIN_LEVEL, AVAILABLE_LEVEL)
            VALUES (0, P_PRINTER_MODEL, i.INK_MODEL, 0, 0, i.QUANTITY);

    ELSIF p_operation = 'UPDATE' THEN
        UPDATE EPROMHQ.INV_INK_LEVEL
        SET AVAILABLE_LEVEL = AVAILABLE_LEVEL - NVL(p_original_quantity, 0) + p_quantity
        WHERE INK_MODEL = p_ink_model;

    ELSIF p_operation = 'DELETE' THEN
        UPDATE EPROMHQ.INV_INK_LEVEL
        SET AVAILABLE_LEVEL = AVAILABLE_LEVEL - NVL(p_original_quantity, 0)
        WHERE INK_MODEL = p_ink_model;


    ELSE
        RAISE_APPLICATION_ERROR(-20001, 'Invalid operation specified');
    END IF;

    COMMIT; -- Commit the transaction
EXCEPTION
    WHEN OTHERS THEN
        ROLLBACK; -- Rollback changes if an error occurs
        RAISE;    -- Propagate the exception
END MANAGE_INK_Addition;
/
