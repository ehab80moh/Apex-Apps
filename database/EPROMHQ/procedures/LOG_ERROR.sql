
  CREATE OR REPLACE EDITIONABLE PROCEDURE "EPROMHQ"."LOG_ERROR"
(
   P_ERROR_MESSAGE IN VARCHAR2,
   P_ERROR_CODE    IN VARCHAR2 DEFAULT NULL,
   P_ERROR_STACK   IN CLOB     DEFAULT NULL,
   P_CALLING_PROC  IN VARCHAR2 DEFAULT NULL
) IS
   PRAGMA AUTONOMOUS_TRANSACTION;  -- ترانزاكشن منفصلة عن الأساسية
   v_stack   CLOB;
BEGIN
   -- لو مش مبعوت الـ stack من برّه، نجيبه من dbms_utility
   IF P_ERROR_STACK IS NULL THEN
      v_stack := DBMS_UTILITY.format_error_backtrace;
   ELSE
      v_stack := P_ERROR_STACK;
   END IF;

   INSERT INTO LOG_ERRORS
          (ERROR_MESSAGE,  ERROR_CODE,  ERROR_STACK, CALLING_PROC)
   VALUES (P_ERROR_MESSAGE, P_ERROR_CODE, v_stack,   P_CALLING_PROC);

   COMMIT; -- كوميت على الترانزاكشن المنفصلة
EXCEPTION
   WHEN OTHERS THEN
      ROLLBACK;  -- رولباك على الترانزاكشن بتاعت اللوج بس
      NULL;      -- متبوّظش الكود الأساسي بسبب مشكلة في اللوج
END LOG_ERROR;
/
