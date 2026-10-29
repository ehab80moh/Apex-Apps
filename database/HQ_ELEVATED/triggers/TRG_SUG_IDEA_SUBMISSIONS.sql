
  CREATE OR REPLACE EDITIONABLE TRIGGER "HQ_ELEVATED"."TRG_SUG_IDEA_SUBMISSIONS"
BEFORE INSERT ON hq_elevated.sug_idea_submissions
FOR EACH ROW
DECLARE
  v_user VARCHAR2(100);
BEGIN
  -- Fallback logic using clean context values
  v_user := COALESCE(
    SYS_CONTEXT('APEX$SESSION', 'APP_USER'),
    SYS_CONTEXT('USERENV', 'SESSION_USER'),
    USER
  );

  IF :NEW.status IS NULL THEN
    :NEW.status := 'SUBMITTED';
  END IF;

  IF :NEW.created_at IS NULL THEN
    :NEW.created_at := SYSDATE;
  END IF;

  IF :NEW.created_by IS NULL THEN
    :NEW.created_by := v_user;
  END IF;

  IF :NEW.emp_number IS NULL THEN
    :NEW.emp_number := v_user;
  END IF;
END;

/
ALTER TRIGGER "HQ_ELEVATED"."TRG_SUG_IDEA_SUBMISSIONS" ENABLE;
