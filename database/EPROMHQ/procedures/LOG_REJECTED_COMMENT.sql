
  CREATE OR REPLACE EDITIONABLE PROCEDURE "EPROMHQ"."LOG_REJECTED_COMMENT" (
    p_task_id          IN NUMBER,
    p_comment_text     IN CLOB,
    p_commented_by     IN VARCHAR2,
    p_rejection_reason IN VARCHAR2
) IS
BEGIN
    INSERT INTO HRF_custom_rejected_comments (
        task_id,
        comment_text,
        commented_by,
        rejection_reason
    ) VALUES (
        p_task_id,
        p_comment_text,
        p_commented_by,
        p_rejection_reason
    );
END;
/
