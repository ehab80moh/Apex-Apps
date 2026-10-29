
  CREATE OR REPLACE EDITIONABLE PACKAGE "HQ_ELEVATED"."APPROVAL_WORKFLOW_PKG" AS

    PROCEDURE create_approval_log (
        p_request_id           IN NUMBER,
        p_request_source       IN VARCHAR2,
        p_request_type_id      IN NUMBER,
        p_emp_id               IN VARCHAR2,
        p_step                 IN NUMBER,
        p_workflow_instance_id IN NUMBER DEFAULT NULL
    );

    PROCEDURE create_next_approval_log (
        p_request_id           IN NUMBER,
        p_request_source       IN VARCHAR2,
        p_request_type_id      IN NUMBER,
        p_emp_id               IN VARCHAR2,
        p_workflow_instance_id IN NUMBER DEFAULT NULL
    );

    PROCEDURE mark_step_approved (
        p_request_id      IN NUMBER,
        p_request_source  IN VARCHAR2,
        p_request_type_id IN NUMBER,
        p_action_by       IN VARCHAR2,
        p_task_id         IN NUMBER DEFAULT NULL,
        p_comment         IN VARCHAR2 DEFAULT NULL
    );

    PROCEDURE mark_step_rejected (
        p_request_id      IN NUMBER,
        p_request_source  IN VARCHAR2,
        p_request_type_id IN NUMBER,
        p_action_by       IN VARCHAR2,
        p_task_id         IN NUMBER DEFAULT NULL,
        p_comment         IN VARCHAR2 DEFAULT NULL
    );

    FUNCTION has_next_step (
        p_request_id      IN NUMBER,
        p_request_source  IN VARCHAR2,
        p_request_type_id IN NUMBER,
        p_emp_id          IN VARCHAR2
    ) RETURN VARCHAR2;


PROCEDURE complete_request_approval (
    p_request_id      IN NUMBER,
    p_request_source  IN VARCHAR2,
    p_request_type_id IN NUMBER,
    p_action_by       IN VARCHAR2
);

PROCEDURE reject_request (
    p_request_id      IN NUMBER,
    p_request_source  IN VARCHAR2,
    p_request_type_id IN NUMBER,
    p_action_by       IN VARCHAR2
);

END approval_workflow_pkg;
/
