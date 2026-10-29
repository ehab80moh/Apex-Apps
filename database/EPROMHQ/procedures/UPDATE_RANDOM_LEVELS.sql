
  CREATE OR REPLACE EDITIONABLE PROCEDURE "EPROMHQ"."UPDATE_RANDOM_LEVELS" AS
  v_added NUMBER;
  v_deducted NUMBER;
  v_exists NUMBER;
BEGIN
  FOR rec IN (
    SELECT MODEL_ID FROM EPROMHQ.INV_RANDOM_MODELS
  ) LOOP
    -- 1. المجموع المضاف
    SELECT NVL(SUM(QUANTITY), 0)
    INTO v_added
    FROM EPROMHQ.INV_RANDOM_ADDITION
    WHERE MODEL_ID = rec.MODEL_ID;

    -- 2. المجموع المخصوم
    SELECT NVL(COUNT(*), 0)
    INTO v_deducted
    FROM EPROMHQ.INV_RANDOM_DEDUCTED
    WHERE MODEL_ID = rec.MODEL_ID;

    -- 3. هل موجود سطر للرصد؟
    SELECT COUNT(*) INTO v_exists
    FROM EPROMHQ.INV_RANDOM_LEVEL
    WHERE MODEL_ID = rec.MODEL_ID;

    IF v_exists > 0 THEN
      UPDATE EPROMHQ.INV_RANDOM_LEVEL
      SET AVAILABLE_LEVEL = v_added - v_deducted
      WHERE MODEL_ID = rec.MODEL_ID;

      DBMS_OUTPUT.PUT_LINE('تم التحديث للموديل: ' || rec.MODEL_ID || ' الرصيد = ' || (v_added - v_deducted));
    ELSE
      INSERT INTO EPROMHQ.INV_RANDOM_LEVEL (
        MODEL_ID,
        AVAILABLE_LEVEL
      ) VALUES (
        rec.MODEL_ID,
        v_added - v_deducted
      );

      DBMS_OUTPUT.PUT_LINE('تم الإدخال للموديل: ' || rec.MODEL_ID || ' الرصيد = ' || (v_added - v_deducted));
    END IF;
  END LOOP;
END;
/
