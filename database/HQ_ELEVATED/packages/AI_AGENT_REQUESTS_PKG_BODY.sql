
  CREATE OR REPLACE EDITIONABLE PACKAGE BODY "HQ_ELEVATED"."AI_AGENT_REQUESTS_PKG" AS

    TYPE t_caller_context IS RECORD (
        session_id NUMBER,
        app_id     NUMBER,
        page_id    NUMBER
    );

    /**
     * Procedure: SWITCH_TO_APP_SESSION (Private helper)
     * Purpose: Saves caller context and switches APEX session to target app (115) for task operations.
     */
    PROCEDURE switch_to_app_session (
        p_target_app_id   IN NUMBER,
        p_target_page_id  IN NUMBER,
        p_username        IN VARCHAR2,
        o_caller_ctx      OUT t_caller_context
    ) IS
        l_workspace_id NUMBER;
    BEGIN
        o_caller_ctx.session_id := v('APP_SESSION');
        o_caller_ctx.app_id     := v('APP_ID');
        o_caller_ctx.page_id    := NVL(v('APP_PAGE_ID'), 1);

        l_workspace_id := apex_util.find_security_group_id('EPROMHQ');
        IF l_workspace_id IS NOT NULL THEN
            apex_util.set_security_group_id(l_workspace_id);
        END IF;

        IF o_caller_ctx.session_id IS NULL OR o_caller_ctx.app_id <> p_target_app_id THEN
            apex_session.create_session (
                p_app_id   => p_target_app_id,
                p_page_id  => p_target_page_id,
                p_username => p_username
            );
        END IF;
    END switch_to_app_session;

    /**
     * Procedure: RESTORE_CALLER_SESSION (Private helper)
     * Purpose: Restores original caller session context.
     */
    PROCEDURE restore_caller_session (
        p_caller_ctx IN t_caller_context
    ) IS
    BEGIN
        IF p_caller_ctx.session_id IS NOT NULL AND p_caller_ctx.app_id IS NOT NULL THEN
            BEGIN
                apex_session.attach (
                    p_app_id     => p_caller_ctx.app_id,
                    p_page_id    => p_caller_ctx.page_id,
                    p_session_id => p_caller_ctx.session_id
                );
            EXCEPTION
                WHEN OTHERS THEN
                    NULL;
            END;
        END IF;
    END restore_caller_session;

    FUNCTION get_user_lang RETURN VARCHAR2 IS
        l_lang VARCHAR2(10);
    BEGIN
        l_lang := lower(APEX_UTIL.GET_SESSION_LANG);
        IF l_lang IS NULL THEN
            l_lang := 'ar-ae'; -- Default to Arabic
        END IF;
        RETURN l_lang;
    END get_user_lang;

    FUNCTION get_session_info RETURN VARCHAR2 IS
        l_lang       VARCHAR2(50);
        l_emp_id     VARCHAR2(50);
        l_emp_name   VARCHAR2(250);
        l_project    VARCHAR2(100);
        l_site       VARCHAR2(100);
        l_mobile     VARCHAR2(50);
        l_json       VARCHAR2(32767);
    BEGIN
        l_lang     := APEX_UTIL.GET_SESSION_LANG;
        l_emp_id   := v('APP_USER');
        l_emp_name := v('EMP_NAME');
        l_project  := v('EMP_PROJECT');
        l_site     := v('EMP_SITE');
        l_mobile   := v('MOBILE');

        l_json := json_object(
            'session_language'   value nvl(l_lang, 'ar-ae'),
            'employee_id'        value l_emp_id,
            'employee_name'      value l_emp_name,
            'employee_project'   value l_project,
            'employee_site'      value l_site,
            'mobile'             value l_mobile,
            'today_date'         value to_char(sysdate, 'YYYY-MM-DD')
        );

        RETURN l_json;
    END get_session_info;

    FUNCTION create_leave_request (
        p_emp_id                 IN  VARCHAR2,
        p_leave_type             IN  VARCHAR2,
        p_from_date              IN  VARCHAR2,
        p_to_date                IN  VARCHAR2,
        p_cover_person           IN  VARCHAR2 DEFAULT NULL
    ) RETURN VARCHAR2 IS
        l_caller_ctx          t_caller_context;
        l_from_date           DATE;
        l_to_date             DATE;
        l_last_working_date   DATE;
        l_return_to_work_date DATE;
        l_contact_address     VARCHAR2(200);
        l_mobile              VARCHAR2(200);
        l_val_res             VARCHAR2(4000);
        l_request_id          NUMBER;
        l_task_id             NUMBER;
        l_seq_no              NUMBER;
        l_success_msg         VARCHAR2(4000);
        l_err_msg             VARCHAR2(4000);
    BEGIN
        -- 1. Switch APEX session context to App 115
        switch_to_app_session(115, 13, p_emp_id, l_caller_ctx);

        -- 2. Convert date inputs
        BEGIN
            l_from_date := TO_DATE(p_from_date, 'YYYY-MM-DD');
            l_to_date   := TO_DATE(p_to_date, 'YYYY-MM-DD');
        EXCEPTION
            WHEN OTHERS THEN
                restore_caller_session(l_caller_ctx);
                l_err_msg := 'Invalid date format. Expected format: YYYY-MM-DD';
                apex_ai.set_tool_result (
                    p_result               => l_err_msg,
                    p_notification_message => l_err_msg,
                    p_notification_type    => apex_ai.c_notification_type_error
                );
                RETURN l_err_msg;
        END;

        -- 3. Auto-calculate fields
        l_last_working_date   := central.xxapex_general.get_last_work_Day(l_from_date);
        l_return_to_work_date := central.xxapex_general.get_return_work_Day(l_to_date);

        IF get_user_lang() = 'ar-ae' THEN
            l_contact_address := 'كما مسجل بالملف';
        ELSE
            l_contact_address := 'As in The file';
        END IF;

        l_mobile              := central.sms_pkg.get_emp_mobile(p_emp_id);

        -- 4. Run validation
        l_val_res := CENTRAL.XXAPEX_SS_VALIDATIONS.xx_validate_leaves(
            p_leave_typ        => p_leave_type,
            p_from_date        => l_from_date,
            p_to_date          => l_to_date,
            p_last_work_date   => l_last_working_date,
            p_return_work_date => l_return_to_work_date,
            p_emp_number       => p_emp_id
        );

        IF l_val_res IS NOT NULL THEN
            restore_caller_session(l_caller_ctx);
            apex_ai.set_tool_result (
                p_result               => l_val_res,
                p_notification_message => l_val_res,
                p_notification_type    => apex_ai.c_notification_type_error
            );
            RETURN l_val_res;
        END IF;

        -- 5. Insert Request
        INSERT INTO EPROMHQ.HRF_EMP_LEAVE_REQUEST (
            emp_id,
            leave_type,
            from_date,
            to_date,
            task_ids,
            updated_by,
            last_working_date,
            return_to_work_date,
            cover_person,
            leave_contact_address,
            mobile,
            approved,
            uploaded_tms
        ) VALUES (
            p_emp_id,
            p_leave_type,
            l_from_date,
            l_to_date,
            NULL,
            p_emp_id,
            l_last_working_date,
            l_return_to_work_date,
            p_cover_person,
            l_contact_address,
            l_mobile,
            0, -- Pending
            0  -- Not uploaded to TMS yet
        ) RETURNING request_id INTO l_request_id;

        -- 6. Query Sequence No for Approval Workflow
        BEGIN
            SELECT approval_sequence
              INTO l_seq_no
              FROM central.apr_approval_result_v
             WHERE request_type_id = 59
               AND approve_type = 'FYA'
               AND emp_number = p_emp_id
               AND approval_sequence = (
                   SELECT MIN(approval_sequence)
                     FROM central.apr_approval_result_v
                    WHERE request_type_id = 59
                      AND approve_type = 'FYA'
                      AND emp_number = p_emp_id
                      AND approver NOT IN ('-1', '-2')
               );
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                l_seq_no := 1;
        END;

        -- 7. Create human task via apex_approval
        l_task_id := apex_approval.create_task (
            p_application_id     => 115,
            p_task_def_static_id => 'LEAVE_REQUEST',
            p_initiator          => p_emp_id,
            p_parameters         => apex_approval.t_task_parameters(
                1 => apex_approval.t_task_parameter(static_id => 'EMP_ID',     string_value => p_emp_id),
                2 => apex_approval.t_task_parameter(static_id => 'FROM_DATE',  string_value => to_char(l_from_date, 'YYYY-MM-DD')),
                3 => apex_approval.t_task_parameter(static_id => 'TO_DATE',    string_value => to_char(l_to_date, 'YYYY-MM-DD')),
                4 => apex_approval.t_task_parameter(static_id => 'SEQ_NO',     string_value => to_char(l_seq_no)),
                5 => apex_approval.t_task_parameter(static_id => 'LEAVE_TYPE', string_value => p_leave_type),
                6 => apex_approval.t_task_parameter(static_id => 'REQUEST_ID', string_value => to_char(l_request_id)),
                7 => apex_approval.t_task_parameter(static_id => 'TASK_IDS',   string_value => null),
                8 => apex_approval.t_task_parameter(static_id => 'UPDATED_BY', string_value => null),
                9 => apex_approval.t_task_parameter(static_id => 'EMP_NAME',   string_value => central.get_emp_name(p_emp_id))
            ),
            p_detail_pk          => NULL
        );

        -- 8. Update task IDs in request
        UPDATE EPROMHQ.HRF_EMP_LEAVE_REQUEST
           SET task_ids = to_char(l_task_id)
         WHERE request_id = l_request_id;

        -- 9. Insert Request Log
        INSERT INTO EPROMHQ.REQUEST_LOG (
            req_id,
            req_start_rotation,
            req_apply_rotation,
            req_type
        ) VALUES (
            l_request_id,
            EPROMHQ.get_emp_rotation(p_emp_id, l_from_date),
            EPROMHQ.get_emp_rotation(p_emp_id, SYSDATE),
            'Leave' || p_leave_type
        );

        COMMIT;

        -- 10. Restore caller session
        restore_caller_session(l_caller_ctx);

        -- 11. Success message and set tool result
        IF get_user_lang() = 'ar-ae' THEN
            l_success_msg := 'تم إنشاء طلب الإجازة بنجاح برقم: ' || l_request_id || ' ورقم المهمة: ' || l_task_id;
        ELSE
            l_success_msg := 'Leave request created successfully. Request ID: ' || l_request_id || ', Task ID: ' || l_task_id;
        END IF;

        apex_ai.set_tool_result (
            p_result               => l_success_msg,
            p_notification_message => l_success_msg,
            p_notification_type    => apex_ai.c_notification_type_success
        );

        RETURN l_success_msg;

    EXCEPTION
        WHEN OTHERS THEN
            restore_caller_session(l_caller_ctx);
            ROLLBACK;
            l_err_msg := SQLERRM;
            apex_ai.set_tool_result (
                p_result               => l_err_msg,
                p_notification_message => l_err_msg,
                p_notification_type    => apex_ai.c_notification_type_error
            );
            RETURN l_err_msg;
    END create_leave_request;

    FUNCTION create_permission_request (
        p_emp_id                 IN  VARCHAR2,
        p_permission_type        IN  VARCHAR2,
        p_reason                 IN  VARCHAR2,
        p_permission_date        IN  VARCHAR2,
        p_from_hour              IN  VARCHAR2,
        p_to_hour                IN  VARCHAR2
    ) RETURN VARCHAR2 IS
        l_caller_ctx          t_caller_context;
        l_perm_date           DATE;
        l_from_hour           DATE;
        l_to_hour             DATE;
        l_mobile              VARCHAR2(200);
        l_val_res             VARCHAR2(4000);
        l_request_id          NUMBER;
        l_task_id             NUMBER;
        l_seq_no              NUMBER;
        l_success_msg         VARCHAR2(4000);
        l_err_msg             VARCHAR2(4000);
    BEGIN
        -- 1. Switch APEX session context to App 115
        switch_to_app_session(115, 45, p_emp_id, l_caller_ctx);

        -- 2. Convert and construct datetime fields
        BEGIN
            l_perm_date := TO_DATE(p_permission_date, 'YYYY-MM-DD');
            l_from_hour := TO_DATE(p_permission_date || ' ' || p_from_hour || ':00', 'YYYY-MM-DD HH24:MI:SS');
            l_to_hour   := TO_DATE(p_permission_date || ' ' || p_to_hour || ':00', 'YYYY-MM-DD HH24:MI:SS');
        EXCEPTION
            WHEN OTHERS THEN
                restore_caller_session(l_caller_ctx);
                l_err_msg := 'Invalid date/time format. Expected: date as YYYY-MM-DD, hours as HH24:MI';
                apex_ai.set_tool_result (
                    p_result               => l_err_msg,
                    p_notification_message => l_err_msg,
                    p_notification_type    => apex_ai.c_notification_type_error
                );
                RETURN l_err_msg;
        END;

        -- 3. Auto-calculate fields
        l_mobile := central.sms_pkg.get_emp_mobile(p_emp_id);

        -- 4. Run validation
        l_val_res := CENTRAL.XXAPEX_SS_VALIDATIONS.xx_validate_permission(
            p_permission_type => p_permission_type,
            p_permission_date => l_perm_date,
            p_permission_from => l_from_hour,
            p_permission_to   => l_to_hour,
            p_emp_number      => p_emp_id
        );

        IF l_val_res IS NOT NULL THEN
            restore_caller_session(l_caller_ctx);
            apex_ai.set_tool_result (
                p_result               => l_val_res,
                p_notification_message => l_val_res,
                p_notification_type    => apex_ai.c_notification_type_error
            );
            RETURN l_val_res;
        END IF;

        -- 5. Insert Request
        INSERT INTO EPROMHQ.HRF_EMP_PERMISSION_REQUEST (
            emp_id,
            permission_type,
            reason,
            permission_date,
            from_hour,
            to_hour,
            updated_by,
            approved,
            uploaded_tms,
            mobile
        ) VALUES (
            p_emp_id,
            p_permission_type,
            p_reason,
            l_perm_date,
            l_from_hour,
            l_to_hour,
            p_emp_id,
            0, -- Pending
            0, -- Not uploaded to TMS yet
            l_mobile
        ) RETURNING request_id INTO l_request_id;

        -- 6. Query Sequence No for Approval Workflow
        BEGIN
            SELECT approval_sequence
              INTO l_seq_no
              FROM central.apr_approval_result_v
             WHERE request_type_id = 61
               AND approve_type = 'FYA'
               AND emp_number = p_emp_id
               AND approval_sequence = (
                   SELECT MIN(approval_sequence)
                     FROM central.apr_approval_result_v
                    WHERE request_type_id = 61
                      AND approve_type = 'FYA'
                      AND emp_number = p_emp_id
                      AND approver NOT IN ('-1', '-2')
               );
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                l_seq_no := 1;
        END;

        -- 7. Create human task via apex_approval
        l_task_id := apex_approval.create_task (
            p_application_id     => 115,
            p_task_def_static_id => 'PERMISSION_REQUEST',
            p_initiator          => p_emp_id,
            p_parameters         => apex_approval.t_task_parameters(
                1 => apex_approval.t_task_parameter(static_id => 'EMP_ID',          string_value => p_emp_id),
                2 => apex_approval.t_task_parameter(static_id => 'PERMISSION_TYPE',  string_value => p_permission_type),
                3 => apex_approval.t_task_parameter(static_id => 'PERMISSION_DATE',  string_value => to_char(l_perm_date, 'YYYY-MM-DD')),
                4 => apex_approval.t_task_parameter(static_id => 'FROM_HOUR',        string_value => to_char(l_from_hour, 'YYYY-MM-DD HH24:MI:SS')),
                5 => apex_approval.t_task_parameter(static_id => 'TO_HOUR',          string_value => to_char(l_to_hour, 'YYYY-MM-DD HH24:MI:SS')),
                6 => apex_approval.t_task_parameter(static_id => 'SEQ_NO',           string_value => to_char(l_seq_no)),
                7 => apex_approval.t_task_parameter(static_id => 'REQUEST_ID',       string_value => to_char(l_request_id)),
                8 => apex_approval.t_task_parameter(static_id => 'TASK_IDS',         string_value => null),
                9 => apex_approval.t_task_parameter(static_id => 'UPDATED_BY',       string_value => null),
                10 => apex_approval.t_task_parameter(static_id => 'EMP_NAME',        string_value => central.get_emp_name(p_emp_id))
            ),
            p_detail_pk          => NULL
        );

        -- 8. Update task IDs in request
        UPDATE EPROMHQ.HRF_EMP_PERMISSION_REQUEST
           SET task_ids = to_char(l_task_id)
         WHERE request_id = l_request_id;

        -- 9. Insert Request Log
        INSERT INTO EPROMHQ.REQUEST_LOG (
            req_id,
            req_start_rotation,
            req_apply_rotation,
            req_type
        ) VALUES (
            l_request_id,
            EPROMHQ.get_emp_rotation(p_emp_id, l_perm_date),
            EPROMHQ.get_emp_rotation(p_emp_id, SYSDATE),
            'Permission' || p_permission_type
        );

        COMMIT;

        -- 10. Restore caller session
        restore_caller_session(l_caller_ctx);

        -- 11. Success message and set tool result
        IF get_user_lang() = 'ar-ae' THEN
            l_success_msg := 'تم إنشاء طلب الإذن بنجاح برقم: ' || l_request_id || ' ورقم المهمة: ' || l_task_id;
        ELSE
            l_success_msg := 'Permission request created successfully. Request ID: ' || l_request_id || ', Task ID: ' || l_task_id;
        END IF;

        apex_ai.set_tool_result (
            p_result               => l_success_msg,
            p_notification_message => l_success_msg,
            p_notification_type    => apex_ai.c_notification_type_success
        );

        RETURN l_success_msg;

    EXCEPTION
        WHEN OTHERS THEN
            restore_caller_session(l_caller_ctx);
            ROLLBACK;
            l_err_msg := SQLERRM;
            apex_ai.set_tool_result (
                p_result               => l_err_msg,
                p_notification_message => l_err_msg,
                p_notification_type    => apex_ai.c_notification_type_error
            );
            RETURN l_err_msg;
    END create_permission_request;

    FUNCTION create_mission_request (
        p_emp_id                 IN  VARCHAR2,
        p_from_date              IN  VARCHAR2,
        p_to_date                IN  VARCHAR2,
        p_request_type_id        IN  NUMBER,
        p_description            IN  VARCHAR2
    ) RETURN VARCHAR2 IS
        l_caller_ctx          t_caller_context;
        l_from_date           DATE;
        l_to_date             DATE;
        l_days                NUMBER;
        l_val_res             VARCHAR2(4000);
        l_request_id          NUMBER;
        l_task_id             NUMBER;
        l_seq_no              NUMBER;
        l_success_msg         VARCHAR2(4000);
        l_err_msg             VARCHAR2(4000);
    BEGIN
        -- 1. Switch APEX session context to App 115
        switch_to_app_session(115, 25, p_emp_id, l_caller_ctx);

        -- 2. Convert date inputs
        BEGIN
            l_from_date := TO_DATE(p_from_date, 'YYYY-MM-DD');
            l_to_date   := TO_DATE(p_to_date, 'YYYY-MM-DD');
        EXCEPTION
            WHEN OTHERS THEN
                restore_caller_session(l_caller_ctx);
                l_err_msg := 'Invalid date format. Expected format: YYYY-MM-DD';
                apex_ai.set_tool_result (
                    p_result               => l_err_msg,
                    p_notification_message => l_err_msg,
                    p_notification_type    => apex_ai.c_notification_type_error
                );
                RETURN l_err_msg;
        END;

        -- 3. Auto-calculate days
        l_days := (l_to_date - l_from_date) + 1;

        -- 4. Run validation
        l_val_res := CENTRAL.XXAPEX_SS_VALIDATIONS.xx_validate_missions(
            p_mission_typ     => to_char(p_request_type_id),
            p_from_date       => l_from_date,
            p_to_date          => l_to_date,
            p_num_of_days     => l_days,
            p_mission_details => p_description,
            p_emp_number      => p_emp_id
        );

        IF l_val_res IS NOT NULL THEN
            restore_caller_session(l_caller_ctx);
            apex_ai.set_tool_result (
                p_result               => l_val_res,
                p_notification_message => l_val_res,
                p_notification_type    => apex_ai.c_notification_type_error
            );
            RETURN l_val_res;
        END IF;

        -- 5. Insert Request
        INSERT INTO EPROMHQ.HRF_EMP_MISSION_REQUEST (
            emp_id,
            from_date,
            to_date,
            request_type_id,
            updated_by,
            description,
            approved,
            uploaded_tms
        ) VALUES (
            p_emp_id,
            l_from_date,
            l_to_date,
            p_request_type_id,
            p_emp_id,
            p_description,
            0, -- Pending
            0  -- Not uploaded to TMS yet
        ) RETURNING request_id INTO l_request_id;

        -- 6. Query Sequence No for Approval Workflow
        BEGIN
            SELECT approval_sequence
              INTO l_seq_no
              FROM central.apr_approval_result_v
             WHERE request_type_id = p_request_type_id
               AND approve_type = 'FYA'
               AND emp_number = p_emp_id
               AND approval_sequence = (
                   SELECT MIN(approval_sequence)
                     FROM central.apr_approval_result_v
                    WHERE request_type_id = p_request_type_id
                      AND approve_type = 'FYA'
                      AND emp_number = p_emp_id
                      AND approver NOT IN ('-1', '-2')
               );
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                l_seq_no := 1;
        END;

        -- 7. Create human task via apex_approval
        l_task_id := apex_approval.create_task (
            p_application_id     => 115,
            p_task_def_static_id => 'MISSION_REQUEST',
            p_initiator          => p_emp_id,
            p_parameters         => apex_approval.t_task_parameters(
                1 => apex_approval.t_task_parameter(static_id => 'EMP_ID',       string_value => p_emp_id),
                2 => apex_approval.t_task_parameter(static_id => 'FROM_DATE',    string_value => to_char(l_from_date, 'YYYY-MM-DD')),
                3 => apex_approval.t_task_parameter(static_id => 'TO_DATE',      string_value => to_char(l_to_date, 'YYYY-MM-DD')),
                4 => apex_approval.t_task_parameter(static_id => 'SEQ_NO',       string_value => to_char(l_seq_no)),
                5 => apex_approval.t_task_parameter(static_id => 'REQ_TYPE_ID',  string_value => to_char(p_request_type_id)),
                6 => apex_approval.t_task_parameter(static_id => 'REQUEST_ID',   string_value => to_char(l_request_id)),
                7 => apex_approval.t_task_parameter(static_id => 'TASK_IDS',     string_value => null),
                8 => apex_approval.t_task_parameter(static_id => 'UPDATED_BY',   string_value => null),
                9 => apex_approval.t_task_parameter(static_id => 'EMP_NAME',     string_value => central.get_emp_name(p_emp_id))
            ),
            p_detail_pk          => NULL
        );

        -- 8. Update task IDs in request
        UPDATE EPROMHQ.HRF_EMP_MISSION_REQUEST
           SET task_ids = to_char(l_task_id)
         WHERE request_id = l_request_id;

        -- 9. Insert Request Log
        INSERT INTO EPROMHQ.REQUEST_LOG (
            req_id,
            req_start_rotation,
            req_apply_rotation,
            req_type
        ) VALUES (
            l_request_id,
            EPROMHQ.get_emp_rotation(p_emp_id, l_from_date),
            EPROMHQ.get_emp_rotation(p_emp_id, SYSDATE),
            'Mission' || p_request_type_id
        );

        COMMIT;

        -- 10. Restore caller session
        restore_caller_session(l_caller_ctx);

        -- 11. Success message and set tool result
        IF get_user_lang() = 'ar-ae' THEN
            l_success_msg := 'تم إنشاء طلب المهمة بنجاح برقم: ' || l_request_id || ' ورقم المهمة: ' || l_task_id;
        ELSE
            l_success_msg := 'Mission request created successfully. Request ID: ' || l_request_id || ', Task ID: ' || l_task_id;
        END IF;

        apex_ai.set_tool_result (
            p_result               => l_success_msg,
            p_notification_message => l_success_msg,
            p_notification_type    => apex_ai.c_notification_type_success
        );

        RETURN l_success_msg;

    EXCEPTION
        WHEN OTHERS THEN
            restore_caller_session(l_caller_ctx);
            ROLLBACK;
            l_err_msg := SQLERRM;
            apex_ai.set_tool_result (
                p_result               => l_err_msg,
                p_notification_message => l_err_msg,
                p_notification_type    => apex_ai.c_notification_type_error
            );
            RETURN l_err_msg;
    END create_mission_request;

END ai_agent_requests_pkg;
/
