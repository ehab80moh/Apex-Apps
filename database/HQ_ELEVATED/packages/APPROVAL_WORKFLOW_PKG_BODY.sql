
  CREATE OR REPLACE EDITIONABLE PACKAGE BODY "HQ_ELEVATED"."APPROVAL_WORKFLOW_PKG" AS

    PROCEDURE create_approval_log (
        p_request_id           IN NUMBER,
        p_request_source       IN VARCHAR2,
        p_request_type_id      IN NUMBER,
        p_emp_id               IN VARCHAR2,
        p_step                 IN NUMBER,
        p_workflow_instance_id IN NUMBER DEFAULT NULL
    )
    AS
        l_log_exists           NUMBER;
        l_potential_approvers  VARCHAR2(1000);
        l_group_name           VARCHAR2(240);
        l_group_type           VARCHAR2(240);
        l_approve_type         VARCHAR2(99);
        l_is_mandatory         VARCHAR2(20);
    BEGIN
        SELECT COUNT(*)
          INTO l_log_exists
          FROM hq_elevated.approval_request_log l
         WHERE l.request_id      = p_request_id
           AND l.request_source  = p_request_source
           AND l.request_type_id = p_request_type_id
           AND l.step_no         = p_step;

        IF l_log_exists > 0 THEN
            RETURN;
        END IF;

        SELECT
            LISTAGG(TRIM(a.approver), ':')
                WITHIN GROUP (ORDER BY a.approver),

            MAX(a.approval_group_name),

            MAX(a.approval_group_type),

            MAX(a.approve_type),

            MAX(a.is_mandatory)
        INTO
            l_potential_approvers,
            l_group_name,
            l_group_type,
            l_approve_type,
            l_is_mandatory
        FROM central.apr_approval_result_v a
        WHERE a.request_type_id   = p_request_type_id
          AND a.emp_number        = p_emp_id
          AND a.approval_sequence = p_step
          AND a.approve_type      = 'FYA'
          AND a.approver IS NOT NULL;

        IF l_potential_approvers IS NULL THEN
            RAISE_APPLICATION_ERROR(
                -20001,
                'Approval setup not found. '
                || 'EMP_ID=' || p_emp_id
                || ', REQUEST_TYPE_ID=' || p_request_type_id
                || ', STEP=' || p_step
            );
        END IF;

        l_potential_approvers :=
            REGEXP_REPLACE(
                TRIM(BOTH ':' FROM l_potential_approvers),
                ':+',
                ':'
            );

        INSERT INTO hq_elevated.approval_request_log (
            request_id,
            request_source,
            request_type_id,
            emp_id,
            step_no,
            potential_approvers,
            approval_group_name,
            approval_group_type,
            approve_type,
            is_mandatory,
            workflow_instance_id,
            action_status,
            created_by,
            created_date
        )
        VALUES (
            p_request_id,
            p_request_source,
            p_request_type_id,
            p_emp_id,
            p_step,
            l_potential_approvers,
            l_group_name,
            l_group_type,
            l_approve_type,
            l_is_mandatory,
            p_workflow_instance_id,
            'PENDING',
            NVL(SYS_CONTEXT('APEX$SESSION', 'APP_USER'), USER),
            SYSDATE
        );

    END create_approval_log;


    PROCEDURE create_next_approval_log (
        p_request_id           IN NUMBER,
        p_request_source       IN VARCHAR2,
        p_request_type_id      IN NUMBER,
        p_emp_id               IN VARCHAR2,
        p_workflow_instance_id IN NUMBER DEFAULT NULL
    )
    AS
        l_last_step NUMBER;
        l_next_step NUMBER;
    BEGIN
        /*
          أول تشغيل:
          لا يوجد Log، فيأخذ أقل Approval Sequence.

          بعد اعتماد Step:
          يأخذ أول Approval Sequence أكبر من آخر Step تم إنشاؤه.
        */
        SELECT NVL(MAX(l.step_no), 0)
          INTO l_last_step
          FROM hq_elevated.approval_request_log l
         WHERE l.request_id      = p_request_id
           AND l.request_source  = p_request_source
           AND l.request_type_id = p_request_type_id;

        SELECT MIN(a.approval_sequence)
          INTO l_next_step
          FROM central.apr_approval_result_v a
         WHERE a.request_type_id   = p_request_type_id
           AND a.emp_number        = p_emp_id
           AND a.approve_type      = 'FYA'
           AND a.approval_sequence > l_last_step
           AND a.approver IS NOT NULL;

        IF l_next_step IS NULL THEN
            RAISE_APPLICATION_ERROR(
                -20002,
                'No next approval step found. '
                || 'REQUEST_ID=' || p_request_id
                || ', EMP_ID=' || p_emp_id
                || ', REQUEST_TYPE_ID=' || p_request_type_id
            );
        END IF;

        create_approval_log(
            p_request_id           => p_request_id,
            p_request_source       => p_request_source,
            p_request_type_id      => p_request_type_id,
            p_emp_id               => p_emp_id,
            p_step                 => l_next_step,
            p_workflow_instance_id => p_workflow_instance_id
        );

    END create_next_approval_log;


    PROCEDURE mark_step_approved (
        p_request_id      IN NUMBER,
        p_request_source  IN VARCHAR2,
        p_request_type_id IN NUMBER,
        p_action_by       IN VARCHAR2,
        p_task_id         IN NUMBER DEFAULT NULL,
        p_comment         IN VARCHAR2 DEFAULT NULL
    )
    AS
    BEGIN
        UPDATE hq_elevated.approval_request_log l
           SET l.action_status  = 'APPROVED',
               l.action_by      = p_action_by,
               l.action_comment = p_comment,
               l.action_date    = SYSDATE,
               l.task_id        = p_task_id,
               l.updated_by     = p_action_by,
               l.updated_date   = SYSDATE
         WHERE l.approval_log_id = (
                   SELECT MAX(x.approval_log_id)
                   FROM hq_elevated.approval_request_log x
                   WHERE x.request_id      = p_request_id
                     AND x.request_source  = p_request_source
                     AND x.request_type_id = p_request_type_id
                     AND x.action_status   = 'PENDING'
               );

        IF SQL%ROWCOUNT = 0 THEN
            RAISE_APPLICATION_ERROR(
                -20003,
                'Pending approval log not found. REQUEST_ID=' || p_request_id
            );
        END IF;
    END mark_step_approved;


    PROCEDURE mark_step_rejected (
        p_request_id      IN NUMBER,
        p_request_source  IN VARCHAR2,
        p_request_type_id IN NUMBER,
        p_action_by       IN VARCHAR2,
        p_task_id         IN NUMBER DEFAULT NULL,
        p_comment         IN VARCHAR2 DEFAULT NULL
    )
    AS
    BEGIN
        UPDATE hq_elevated.approval_request_log l
           SET l.action_status  = 'REJECTED',
               l.action_by      = p_action_by,
               l.action_comment = p_comment,
               l.action_date    = SYSDATE,
               l.task_id        = p_task_id,
               l.updated_by     = p_action_by,
               l.updated_date   = SYSDATE
         WHERE l.approval_log_id = (
                   SELECT MAX(x.approval_log_id)
                   FROM hq_elevated.approval_request_log x
                   WHERE x.request_id      = p_request_id
                     AND x.request_source  = p_request_source
                     AND x.request_type_id = p_request_type_id
                     AND x.action_status   = 'PENDING'
               );

        IF SQL%ROWCOUNT = 0 THEN
            RAISE_APPLICATION_ERROR(
                -20004,
                'Pending approval log not found. REQUEST_ID=' || p_request_id
            );
        END IF;
    END mark_step_rejected;


    FUNCTION has_next_step (
        p_request_id      IN NUMBER,
        p_request_source  IN VARCHAR2,
        p_request_type_id IN NUMBER,
        p_emp_id          IN VARCHAR2
    ) RETURN VARCHAR2
    AS
        l_last_step NUMBER;
        l_count     NUMBER;
    BEGIN
        SELECT NVL(MAX(l.step_no), 0)
          INTO l_last_step
          FROM hq_elevated.approval_request_log l
         WHERE l.request_id      = p_request_id
           AND l.request_source  = p_request_source
           AND l.request_type_id = p_request_type_id;

        SELECT COUNT(*)
          INTO l_count
          FROM central.apr_approval_result_v a
         WHERE a.request_type_id   = p_request_type_id
           AND a.emp_number        = p_emp_id
           AND a.approve_type      = 'FYA'
           AND a.approval_sequence > l_last_step
           AND a.approver IS NOT NULL;

        RETURN CASE
                   WHEN l_count > 0 THEN 'Y'
                   ELSE 'N'
               END;
    END has_next_step;



PROCEDURE complete_request_approval (
    p_request_id      IN NUMBER,
    p_request_source  IN VARCHAR2,
    p_request_type_id IN NUMBER,
    p_action_by       IN VARCHAR2
)
AS
    l_request_source VARCHAR2(100);
BEGIN
    l_request_source := UPPER(TRIM(p_request_source));

    /*
      Generic workflow:
      كل نوع طلب له update خاص به هنا.
    */
    CASE l_request_source

        WHEN 'ITR_REQUESTS' THEN
            UPDATE hq_elevated.itr_requests
               SET approved           = 1,
                   status             = 20,
                   last_approval_date = SYSDATE,
                   updated_by         = SYSDATE
             WHERE request_id = p_request_id;

        /*
          أضف باقي الأنواع هنا لاحقًا.

        WHEN 'VAC_REQUESTS' THEN
            UPDATE epromhq.vac_requests
               SET status = 'APPROVED',
                   approved_by = p_action_by,
                   approved_date = SYSDATE
             WHERE request_id = p_request_id;

        WHEN 'TRAVEL_REQUESTS' THEN
            UPDATE epromhq.travel_requests
               SET status = 'APPROVED'
             WHERE request_id = p_request_id;
        */

        ELSE
            RAISE_APPLICATION_ERROR(
                -20010,
                'Unsupported REQUEST_SOURCE for final approval: '
                || p_request_source
            );
    END CASE;

    IF SQL%ROWCOUNT = 0 THEN
        RAISE_APPLICATION_ERROR(
            -20011,
            'Request not found. REQUEST_ID=' || p_request_id
            || ', REQUEST_SOURCE=' || p_request_source
        );
    END IF;
END complete_request_approval;


PROCEDURE reject_request (
    p_request_id      IN NUMBER,
    p_request_source  IN VARCHAR2,
    p_request_type_id IN NUMBER,
    p_action_by       IN VARCHAR2
)
AS
    l_request_source VARCHAR2(100);
BEGIN
    l_request_source := UPPER(TRIM(p_request_source));

    CASE l_request_source

        WHEN 'ITR_REQUESTS' THEN
            UPDATE hq_elevated.itr_requests
               SET approved           = 0,
                   status             = 150,
                   last_approval_date = SYSDATE,
                   updated_by         = SYSDATE
             WHERE request_id = p_request_id;

        ELSE
            RAISE_APPLICATION_ERROR(
                -20012,
                'Unsupported REQUEST_SOURCE for rejection: '
                || p_request_source
            );
    END CASE;

    IF SQL%ROWCOUNT = 0 THEN
        RAISE_APPLICATION_ERROR(
            -20013,
            'Request not found. REQUEST_ID=' || p_request_id
            || ', REQUEST_SOURCE=' || p_request_source
        );
    END IF;
END reject_request;

END approval_workflow_pkg;
/
