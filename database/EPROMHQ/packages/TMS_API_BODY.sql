
  CREATE OR REPLACE EDITIONABLE PACKAGE BODY "EPROMHQ"."TMS_API" AS
------------------------------------------------------------
-------------------------------------------------------------------VACATIONS---------------------------------------------------
    PROCEDURE upload_tms_vacations AS
    /*
This procedure appears to upload employee leave
requests to a system. It does this by iterating
through records in the hrf_emp_leave_request table and,
for each record, it determines if it's a "Regular Rotation Plan"
or not. If it is, it cuts weekends and inserts vacations; otherwise,
it inserts TMS (Time Management System) vacations.
    */

        v_rot_plan VARCHAR2(99) := '';
         -- Define a cursor to fetch eligible leave requests.
        CURSOR cr IS
        SELECT
            *
        FROM
            hrf_emp_leave_request
        WHERE
                uploaded_tms = 0
            AND approved = 1
            AND tms_id IS NULL;

    BEGIN
        IF sys_context('userenv', 'server_host') <> 'apex' THEN
            RETURN;
        END IF;

        FOR c IN cr LOOP
            -- Lock the row to prevent concurrent processing
            DECLARE
                v_lock_id NUMBER;
            BEGIN
                SELECT request_id
                INTO v_lock_id
                FROM hrf_emp_leave_request
                WHERE request_id = c.request_id
                  AND uploaded_tms = 0
                  AND tms_id IS NULL
                FOR UPDATE NOWAIT;
            EXCEPTION
                WHEN OTHERS THEN
                    CONTINUE;
            END;

--            -- check if regular plan -- then cut
--            BEGIN
--
--
--                SELECT
--                    rotation_plan_name
--                INTO v_rot_plan
--                FROM
--                    central.xxapex_otl_leave_credit
--                WHERE
--                    employee_number = c.emp_id;
--
--            EXCEPTION
--                WHEN no_data_found THEN
--                    NULL;
--            END;
            --check day or shift
      v_rot_plan :=central.xxapex_employee_data.get_emp_rotation_plan(c.emp_id,c.from_date);
    -- Call the appropriate function based on the type of leave request.

            IF v_rot_plan = 'Day' THEN
                cut_weekends_and_insert_vacations(p_from => c.from_date, p_to => c.to_date, p_leave_type => c.leave_type, p_emp_id =>
                c.emp_id, p_request_id => c.request_id);

            ELSE
                insert_tms_vacation(p_from => c.from_date, p_to => c.to_date, p_leave_type => c.leave_type, p_emp_id => c.emp_id, p_request_id =>
                c.request_id);
            END IF;

        END LOOP;
    END upload_tms_vacations;

    -- Define the "cut_weekends_and_insert_vacations" procedure.

    ------------------------------------------------------------
    PROCEDURE cut_weekends_and_insert_vacations (
        p_from       DATE,
        p_to         DATE,
        p_leave_type VARCHAR2,
        p_emp_id     VARCHAR2,
        p_request_id NUMBER
    ) AS
        v_from DATE;
        v_to   DATE;
    BEGIN
      -- Iterate through each day within the specified date range.

    ---loop every day
        FOR i IN 0..( p_to - p_from ) LOOP
            -- Check if the current day is not a weekend and not a holiday.

--if not week ends
            IF
                to_char(p_from + i, 'dy') NOT IN ( 'fri', 'sat' )
                AND NOT tms_api.in_holiday(p_from + i)

            THEN
-- If "v_from" is null, it's the start of a vacation period.
                IF v_from IS NULL THEN
                    v_from := p_from + i;
                END IF;
-- Check if the next day is a weekend, a holiday, or the last day in the range.
--if next day is week end then cut.
                IF ( to_char(p_from + i + 1, 'dy') IN ( 'fri', 'sat' ) OR tms_api.in_holiday(p_from + i + 1) ) OR i = ( p_to - p_from )
                THEN
                    v_to := p_from + i;
-- Send the vacation period to the TMS.
                    insert_tms_vacation(p_from => v_from, p_to => v_to, p_leave_type => p_leave_type, p_emp_id => p_emp_id, p_request_id =>
                    p_request_id);

                END IF;

            ELSE
                v_from := NULL;
            END IF;
        END LOOP;
    END cut_weekends_and_insert_vacations;
------------------------------------------------------------
-- Define the "delete_tms_vacations" procedure.
    PROCEDURE delete_tms_vacations AS
  -- Define a cursor to fetch eligible leave requests for deletion.

        CURSOR cr IS
        SELECT
            *
        FROM
            hrf_emp_leave_request
        WHERE
                delete_tms = 0
            AND delete_approved = 1
            AND tms_id IS NOT NULL;
  -- Define a cursor to extract TMS IDs in the format "xxxxx:zzzzz."
        CURSOR tms_ids (
            v_tms_ids VARCHAR2
        ) IS
        SELECT
            column_value AS id
        FROM
            TABLE ( apex_string.split(v_tms_ids, ':') );

    BEGIN
        IF sys_context('userenv', 'server_host') <> 'apex' THEN
            RETURN;
        END IF;

      -- Iterate through eligible leave requests.
        FOR c IN cr LOOP
    -- Iterate through TMS IDs in the "xxxxx:zzzzz" format.
            FOR t IN tms_ids(c.tms_id) LOOP
                  -- Call the "delete_tms_vacation" function for each TMS ID.
                delete_tms_vacation(p_tms_id => t.id, p_request_id => c.request_id);
            END LOOP;
        END LOOP;
    END delete_tms_vacations;
------------------------------------------------------------
-- Define the "delete_tms_vacation" procedure.
    PROCEDURE delete_tms_vacation (
        p_tms_id     NUMBER,
        p_request_id NUMBER
    ) AS
        sqlerr   VARCHAR2(4000);
        v_tms_id VARCHAR2(99);
        l_clob   CLOB;
    BEGIN
        BEGIN
            -- Set request headers for a REST API call.
            apex_web_service.g_request_headers.DELETE();
            apex_web_service.g_request_headers(1).name := 'Content-Type';
            apex_web_service.g_request_headers(1).value := 'application/json';
            l_clob := apex_web_service.make_rest_request(p_url => 'http://tms.eprom.com.eg:8091/Vacation/delete?VacationID=' || apex_util.
            url_encode(p_tms_id), p_http_method => 'POST', p_username => 'apex',
--,p_credential_static_id  => 'Credentials_for_tms_vacation'
-- Make a REST API request to delete a TMS vacation.
             p_password => 'Mijdfsbfd$vsd43fsdf', p_parm_name => apex_string.string_to_table('VacationID'),
                                                        p_parm_value => apex_string.string_to_table(p_tms_id));
-- If the request is successful (HTTP status code 200), update the leave request status.
            IF apex_web_service.g_status_code = 200 THEN
                v_tms_id := CAST ( l_clob AS VARCHAR2 );
                UPDATE hrf_emp_leave_request
                SET
                    delete_tms = 1
                WHERE
                    request_id = p_request_id;

            END IF;
-- Insert a log entry for the request.
            INSERT INTO tms_api_log (
                request_id,
                log,
                stat
            ) VALUES (
                p_request_id,
                l_clob,
                apex_web_service.g_status_code || ' - LEAVE'
            );

            COMMIT;
        EXCEPTION
            WHEN OTHERS THEN
                sqlerr := sqlerrm;
      -- Insert an error log entry for the request.
                INSERT INTO tms_api_log (
                    request_id,
                    log,
                    stat
                ) VALUES (
                    p_request_id,
                    sqlerr,
                    apex_web_service.g_status_code
                );

                COMMIT;
        END;
    END;

------------------------------------------------------------
-- Define the "insert_tms_vacation" procedure.
    PROCEDURE insert_tms_vacation (
        p_from       DATE,
        p_to         DATE,
        p_leave_type VARCHAR2,
        p_emp_id     VARCHAR2,
        p_request_id NUMBER
    ) AS
        sqlerr   VARCHAR2(4000);
        v_tms_id VARCHAR2(99);
        l_clob   CLOB;
    BEGIN
      -- Set request headers for a REST API call.
        apex_web_service.g_request_headers.DELETE();
        apex_web_service.g_request_headers(1).name := 'Content-Type';
        apex_web_service.g_request_headers(1).value := 'application/json';
          -- Make a REST API request to add a TMS vacation.
        l_clob := apex_web_service.make_rest_request(p_url => 'http://tms.eprom.com.eg:8091/Vacation/add?Code='
                                                              || apex_util.url_encode(p_leave_type)
                                                              || '&FromDate='
                                                              || apex_util.url_encode(to_char(p_from, 'mm/dd/yyyy'))
                                                              || '&ToDate='
                                                              || apex_util.url_encode(to_char(p_to, 'mm/dd/yyyy'))
                                                              || '&EmployeeNumber='
                                                              || apex_util.url_encode(p_emp_id), p_http_method => 'POST', p_username =>
                                                              'apex',
--,p_credential_static_id  => 'Credentials_for_tms_vacation'
                                                               p_password => 'Mijdfsbfd$vsd43fsdf', p_parm_name => apex_string.string_to_table(
                                                              'Code'), --any content
                                                    p_parm_value => apex_string.string_to_table('H') --any content does not matter
                                                    );
  -- If the request is successful (HTTP status code 200), update the leave request status.
        IF apex_web_service.g_status_code = 200 THEN
            v_tms_id := CAST ( l_clob AS VARCHAR2 );
            UPDATE hrf_emp_leave_request
            SET
                uploaded_tms = 1,
                tms_id = nvl(tms_id, '')
                         || ':'
                         || v_tms_id
            WHERE
                request_id = p_request_id;

        ELSIF apex_web_service.g_status_code = 418 THEN
-- If the request returns HTTP status code 418, update the leave request status to "approved = 4".
            UPDATE hrf_emp_leave_request
            SET
                approved = 4
            WHERE
                request_id = p_request_id;

  --send notification
                central.xxapex_emp_notifications.add_notification(
                p_emp_id => p_emp_id,
                p_title => 'طلب اجازة  ' ,
                p_body => 'تم الالغاء لتأخر المدير الاعتماد فى شهر الطلب',
                p_app_id => 104,
                p_page_id => 100,
                p_task_id => 'Request ID:'|| p_request_id,
                p_status => 3
                );
        END IF;
  -- Insert a log entry for the request.
        INSERT INTO tms_api_log (
            request_id,
            log,
            stat
        ) VALUES (
            p_request_id,
            l_clob,
            apex_web_service.g_status_code || ' - LEAVE'
        );

        COMMIT;
    EXCEPTION
        WHEN OTHERS THEN
            sqlerr := sqlerrm;
        -- Insert an error log entry for the request.
            INSERT INTO tms_api_log (
                request_id,
                log,
                stat
            ) VALUES (
                p_request_id,
                sqlerr,
                apex_web_service.g_status_code
            );

            COMMIT;
    END insert_tms_vacation;
-------------------------------------------------------------------END VACATIONS---------------------------------------------------

-------------------------------------------------------------------Missions---------------------------------------------------
    PROCEDURE upload_tms_missions IS

        CURSOR cr IS
        SELECT
            *
        FROM
            hrf_emp_mission_request
        WHERE
                uploaded_tms = 0
            AND approved = 1
            AND tms_id IS NULL;
  -- Declare variables to store mission type and rotation plan name.
        v_type     VARCHAR2(9);
        v_rot_plan VARCHAR2(99) := '';
    BEGIN
        IF sys_context('userenv', 'server_host') <> 'apex' THEN
            RETURN;
        END IF;

        FOR c IN cr LOOP
            -- Lock the row to prevent concurrent processing
            DECLARE
                v_lock_id NUMBER;
            BEGIN
                SELECT request_id
                INTO v_lock_id
                FROM hrf_emp_mission_request
                WHERE request_id = c.request_id
                  AND uploaded_tms = 0
                  AND tms_id IS NULL
                FOR UPDATE NOWAIT;
            EXCEPTION
                WHEN OTHERS THEN
                    CONTINUE;
            END;
    -- Check if it's a "Regular Rotation Plan."
--            BEGIN
--                SELECT
--                    rotation_plan_name
--                INTO v_rot_plan
--                FROM
--                    central.xxapex_otl_leave_credit
--                WHERE
--                    employee_number = c.emp_id;
--
--            EXCEPTION
--                WHEN no_data_found THEN
--                    NULL;
--            END;
--get day or shift
v_rot_plan :=central.xxapex_employee_data.get_emp_rotation_plan(c.emp_id,c.from_date);
    -- Determine the mission type based on the request type ID To send to tms.
        ---get mission type to send to tms
            IF c.request_type_id = 72 THEN
                v_type := 'B';
            ELSIF c.request_type_id = 121 THEN
                v_type := 'T';
            END IF;

    -- Call the appropriate function based on the rotation plan and mission type.
            IF v_rot_plan = 'Day' THEN
                cut_weekends_and_insert_missions(p_from => c.from_date, p_to => c.to_date, p_description => c.description, p_emp_id =>
                c.emp_id, p_request_id => c.request_id,
                                                p_type => v_type);
            ELSE
                insert_tms_mission(p_from => c.from_date, p_to => c.to_date, p_description => c.description, p_emp_id => c.emp_id, p_request_id =>
                c.request_id,
                                  p_type => v_type);
            END IF;

        END LOOP;
    END;
------------------------------------------------------------
-- Define the "cut_weekends_and_insert_missions" procedure.
    PROCEDURE cut_weekends_and_insert_missions (
        p_from        DATE,
        p_to          DATE,
        p_description VARCHAR2,
        p_emp_id      VARCHAR2,
        p_request_id  NUMBER,
        p_type        VARCHAR2
    ) AS
        v_from DATE;
        v_to   DATE;
    BEGIN
  -- Iterate through each day within the specified date range.
        FOR i IN 0..( p_to - p_from ) LOOP
-- Check if the current day is not a weekend and not a holiday.
--if not week ends
            IF
                to_char(p_from + i, 'dy') NOT IN ( 'fri', 'sat' )
                AND NOT tms_api.in_holiday(p_from + i)
            THEN
-- If "v_from" is null, it's the start of a mission period.
--if v_from is null then start day
                IF v_from IS NULL THEN
                    v_from := p_from + i;
                END IF;
-- Check if the next day is a weekend, a holiday, or the last day in the range then cut.
                IF ( to_char(p_from + i + 1, 'dy') IN ( 'fri', 'sat' ) OR tms_api.in_holiday(p_from + i + 1) ) OR i = ( p_to - p_from )
                THEN
                    v_to := p_from + i;
-- Send the mission period to the TMS.

                    insert_tms_mission(p_from => v_from, p_to => v_to, p_description => p_description, p_emp_id => p_emp_id, p_request_id =>

                    p_request_id,
                                      p_type => p_type);

                END IF;

            ELSE
                v_from := NULL;
            END IF;
        END LOOP;
    END cut_weekends_and_insert_missions;
------------------------------------------------------------
-- Define the "delete_tms_missions" procedure.
    PROCEDURE delete_tms_missions
      /*
  This procedure is responsible for deleting mission data from the TMS for approved
  deletion requests. It retrieves eligible deletion requests and associated mission IDs
  in the format "xxxxx:zzzzz" and sends deletion requests to the TMS accordingly.
  */
    IS
  -- Declare a cursor to fetch eligible deletion requests.
        CURSOR cr IS
        SELECT
            *
        FROM
            hrf_emp_mission_request
        WHERE
                delete_tms = 0
            AND delete_approved = 1
            AND tms_id IS NOT NULL;

  -- Declare a cursor to extract TMS IDs in the "xxxxx:zzzzz" format.
        CURSOR tms_ids (
            v_tms_ids VARCHAR2
        ) IS
        SELECT
            column_value AS id
        FROM
            TABLE ( apex_string.split(v_tms_ids, ':') );

        v_type VARCHAR2(9);

-- Iterate through eligible deletion requests.
    BEGIN
        IF sys_context('userenv', 'server_host') <> 'apex' THEN
            RETURN;
        END IF;

        FOR c IN cr LOOP
    -- Determine the mission type based on the request type ID.
            IF c.request_type_id = 72 THEN
                v_type := 'B';
            ELSIF c.request_type_id = 121 THEN
                v_type := 'T';
            END IF;

-- Iterate through TMS IDs in the "xxxxx:zzzzz" format and call the deletion function.
            FOR t IN tms_ids(c.tms_id) LOOP
                delete_tms_mission(p_tms_id => t.id, p_request_id => c.request_id, p_type => v_type);
            END LOOP;

        END LOOP;
    END;
------------------------------------------------------------
-- Define the "insert_tms_mission" procedure.
    PROCEDURE insert_tms_mission (
        p_from        DATE,
        p_to          DATE,
        p_description VARCHAR2,
        p_emp_id      VARCHAR2,
        p_request_id  NUMBER,
        p_type        VARCHAR2
    ) IS
        sqlerr   VARCHAR2(4000);
        v_tms_id VARCHAR2(99);
        l_clob   CLOB;
    BEGIN
        apex_web_service.g_request_headers.DELETE();
        apex_web_service.g_request_headers(1).name := 'Content-Type';
        apex_web_service.g_request_headers(1).value := 'application/json';
          -- Make a REST API request to add a mission.
        l_clob := apex_web_service.make_rest_request(p_url => 'http://tms.eprom.com.eg:8091/Mission/add?Description='
                                                              || utl_url.escape(url => p_description, url_charset => 'AL32UTF8')
                                                              || '&FromDate='
                                                              || apex_util.url_encode(to_char(p_from, 'mm/dd/yyyy'))
                                                              || '&ToDate='
                                                              || apex_util.url_encode(to_char(p_to, 'mm/dd/yyyy'))
                                                              || '&EmployeeNumber='
                                                              || apex_util.url_encode(p_emp_id)
                                                              || '&Type='
                                                              || apex_util.url_encode(p_type), p_http_method => 'POST', p_username =>
                                                              'apex',
--,p_credential_static_id  => 'Credentials_for_tms_vacation'
                                                               p_password => 'Mijdfsbfd$vsd43fsdf', p_parm_name => apex_string.string_to_table(
                                                              'ANY'), --any content
                                                    p_parm_value => apex_string.string_to_table('THING') --any content does not matter
                                                    );
  -- If the request is successful (HTTP status code 200), update the mission status.
        IF apex_web_service.g_status_code = 200 THEN
            v_tms_id := CAST ( l_clob AS VARCHAR2 );
            UPDATE hrf_emp_mission_request
            SET
                uploaded_tms = 1,
                tms_id = nvl(tms_id, '')
                         || ':'
                         || v_tms_id
            WHERE
                request_id = p_request_id;

        ELSIF apex_web_service.g_status_code = 418 THEN
            UPDATE hrf_emp_mission_request
            SET
                approved = 4
            WHERE
                request_id = p_request_id;
  --send notification
                central.xxapex_emp_notifications.add_notification(
                p_emp_id => p_emp_id,
                p_title => ' طلب مهمه' ,
                p_body => 'تم الالغاء لتأخر المدير الاعتماد فى شهر الطلب',
                p_app_id => 104,
                p_page_id => 100,
                p_task_id => 'Request ID:'|| p_request_id,
                p_status => 3
                );
        END IF;
--insert request log
        INSERT INTO tms_api_log (
            request_id,
            log,
            stat
        ) VALUES (
            p_request_id,
            l_clob,
            apex_web_service.g_status_code || ' - MISSION'
        );

        COMMIT;
    EXCEPTION
        WHEN OTHERS THEN
            sqlerr := sqlerrm;
            INSERT INTO tms_api_log (
                request_id,
                log,
                stat
            ) VALUES (
                p_request_id,
                sqlerr,
                apex_web_service.g_status_code || ' - MISSION'
            );

            COMMIT;
    END;
------------------------------------------------------------
    PROCEDURE delete_tms_mission
    -- Define the "insert_tms_mission" procedure.
    (
        p_tms_id     NUMBER,
        p_request_id NUMBER,
        p_type       VARCHAR2
    ) IS
        sqlerr   VARCHAR2(4000);
        v_tms_id VARCHAR2(99);
        l_clob   CLOB;
    BEGIN
        apex_web_service.g_request_headers.DELETE();
        apex_web_service.g_request_headers(1).name := 'Content-Type';
        apex_web_service.g_request_headers(1).value := 'application/json';
        l_clob := apex_web_service.make_rest_request(p_url => 'http://tms.eprom.com.eg:8091/Mission/delete?MissionID='
                                                              || apex_util.url_encode(p_tms_id)
                                                              || '&Type='
                                                              || apex_util.url_encode(p_type), p_http_method => 'POST', p_username =>
                                                              'apex',
--,p_credential_static_id  => 'Credentials_for_tms_vacation'
                                                               p_password => 'Mijdfsbfd$vsd43fsdf', p_parm_name => apex_string.string_to_table(
                                                              'MissionID'),
                                                    p_parm_value => apex_string.string_to_table(p_tms_id));
  -- If the request is successful (HTTP status code 200), update the mission status.
        IF apex_web_service.g_status_code = 200 THEN
            v_tms_id := CAST ( l_clob AS VARCHAR2 );
            UPDATE hrf_emp_mission_request
            SET
                delete_tms = 1
            WHERE
                request_id = p_request_id;

        END IF;
  -- Insert a log entry for the request.
        INSERT INTO tms_api_log (
            request_id,
            log,
            stat
        ) VALUES (
            p_request_id,
            l_clob,
            apex_web_service.g_status_code || ' - MISSION'
        );

        COMMIT;
    EXCEPTION
        WHEN OTHERS THEN
            sqlerr := sqlerrm;
            -- Insert an error log entry for the request.
            INSERT INTO tms_api_log (
                request_id,
                log,
                stat
            ) VALUES (
                p_request_id,
                sqlerr,
                apex_web_service.g_status_code || ' - MISSION'
            );

            COMMIT;
    END;
------------------------------------------------------------
-------------------------------------------------------------------END Missions---------------------------------------------------

-------------------------------------------------------------------Permissions---------------------------------------------------
    PROCEDURE upload_tms_permissions AS
        CURSOR cr IS
        SELECT
            *
        FROM
            hrf_emp_permission_request
        WHERE
                uploaded_tms = 0
            AND approved = 1
            AND tms_id IS NULL;

    BEGIN
        IF sys_context('userenv', 'server_host') <> 'apex' THEN
            RETURN;
        END IF;

        FOR c IN cr LOOP
            -- Lock the row to prevent concurrent processing
            DECLARE
                v_lock_id NUMBER;
            BEGIN
                SELECT request_id
                INTO v_lock_id
                FROM hrf_emp_permission_request
                WHERE request_id = c.request_id
                  AND uploaded_tms = 0
                  AND tms_id IS NULL
                FOR UPDATE NOWAIT;
            EXCEPTION
                WHEN OTHERS THEN
                    CONTINUE;
            END;
            insert_tms_permission(p_date => c.permission_date, p_from => c.from_hour, p_to => c.to_hour, p_code => c.permission_type,
            p_desc => c.reason,
                                 p_emp_id => c.emp_id, p_request_id => c.request_id);
        END LOOP;
    END;
------------------------------------------------------------
-- Delete TMS Permissions Procedure
    PROCEDURE delete_tms_permissions AS
     /*
    This procedure is responsible for processing deletion requests for Time Management System (TMS) permissions.
    It iterates through eligible permission records, initiates a deletion request for each,
    and updates the relevant status upon successful completion.
    */

    -- Cursor to retrieve eligible deletion requests.
        CURSOR cr IS
        SELECT
            *
        FROM
            hrf_emp_permission_request
        WHERE
                delete_tms = 0
            AND delete_approved = 1
            AND tms_id IS NOT NULL;
    -- Iterate through eligible deletion requests and call the delete_tms_permission function.
    BEGIN
        IF sys_context('userenv', 'server_host') <> 'apex' THEN
            RETURN;
        END IF;

        FOR c IN cr LOOP
            delete_tms_permission(p_tms_id => c.tms_id, p_request_id => c.request_id);
        END LOOP;
    END;
------------------------------------------------------------
-- Insert TMS Permission Procedure
    PROCEDURE insert_tms_permission (
        p_date       DATE,
        p_from       DATE,
        p_to         DATE,
        p_code       VARCHAR2,
        p_desc       VARCHAR2,
        p_emp_id     VARCHAR2,
        p_request_id NUMBER
    ) AS
     /*
    This procedure handles the insertion of permissions into the Time Management System (TMS).
    It constructs a JSON-based REST API request with permission details, sends the request to TMS,
    and processes the response, updating the status of the corresponding permission request.
    */
        sqlerr   VARCHAR2(4000);
        v_tms_id VARCHAR2(99);
        l_clob   CLOB;
    BEGIN
        -- Set request headers for the REST API call.
        apex_web_service.g_request_headers.DELETE();
        apex_web_service.g_request_headers(1).name := 'Content-Type';
        apex_web_service.g_request_headers(1).value := 'application/json';
            -- Make a REST API request to add a permission.
        l_clob := apex_web_service.make_rest_request(p_url => 'http://tms.eprom.com.eg:8091/Permission/add?Description='
                                                              || utl_url.escape(url => p_desc, url_charset => 'AL32UTF8')
                                                              || '&Code='
                                                              || p_code
                                                              || '&Date='
                                                              || apex_util.url_encode(to_char(p_date, 'mm/dd/yyyy'))
                                                              || '&FromTime='
                                                              || apex_util.url_encode(to_char(p_from, 'mm/dd/yyyy hh24:mi'))
                                                              || '&ToTime='
                                                              || apex_util.url_encode(to_char(p_to, 'mm/dd/yyyy hh24:mi'))
                                                              || '&EmployeeNumber='
                                                              || apex_util.url_encode(p_emp_id), p_http_method => 'POST', p_username =>
                                                              'apex',
--,p_credential_static_id  => 'Credentials_for_tms_vacation'
                                                               p_password => 'Mijdfsbfd$vsd43fsdf', p_parm_name => apex_string.string_to_table(
                                                              'ANY'), --any content
                                                    p_parm_value => apex_string.string_to_table('THING') --any content does not matter
                                                    );
    -- Process the response from the API request.
        IF apex_web_service.g_status_code = 200 THEN
    -- If the request is successful, update the uploaded status and TMS ID.
            v_tms_id := CAST ( l_clob AS VARCHAR2 );
            UPDATE hrf_emp_permission_request
            SET
                uploaded_tms = 1,
                tms_id = v_tms_id
            WHERE
                request_id = p_request_id;

        ELSIF apex_web_service.g_status_code = 418 THEN
    -- If the request returns HTTP status code 418, update the approval status.
            UPDATE hrf_emp_permission_request
            SET
                approved = 4
            WHERE
                request_id = p_request_id;
  --send notification
                central.xxapex_emp_notifications.add_notification(
                p_emp_id => p_emp_id,
                p_title => 'طلب اذن ' ,
                p_body => 'تم الالغاء لتأخر المدير الاعتماد فى شهر الطلب',
                p_app_id => 104,
                p_page_id => 100,
                p_task_id => 'Request ID:'|| p_request_id,
                p_status => 3
                );
        END IF;
    -- Insert a log entry for the request.
        INSERT INTO tms_api_log (
            request_id,
            log,
            stat
        ) VALUES (
            p_request_id,
            l_clob,
            apex_web_service.g_status_code || ' - PERMISSION'
        );

        COMMIT;
    EXCEPTION
        WHEN OTHERS THEN
            sqlerr := sqlerrm;
    -- Handle exceptions and log errors.
            INSERT INTO tms_api_log (
                request_id,
                log,
                stat
            ) VALUES (
                p_request_id,
                sqlerr,
                apex_web_service.g_status_code || ' - PERMISSION'
            );

            COMMIT;
    END;
------------------------------------------------------------
    -- Delete TMS Permission Procedure
    PROCEDURE delete_tms_permission (
        p_tms_id     NUMBER,
        p_request_id NUMBER
    ) AS
     /*
    This procedure sends a request to delete a permission record from the Time Management System (TMS).
    It processes the API response and updates the deletion status accordingly.
    */

        sqlerr   VARCHAR2(4000);
        v_tms_id VARCHAR2(99);
        l_clob   CLOB;
    -- Set request headers for the REST API call.
    BEGIN
        apex_web_service.g_request_headers.DELETE();
        apex_web_service.g_request_headers(1).name := 'Content-Type';
        apex_web_service.g_request_headers(1).value := 'application/json';
            -- Make a REST API request to delete a permission.
        l_clob := apex_web_service.make_rest_request(p_url => 'http://tms.eprom.com.eg:8091/Permission/delete?PermissionID=' || apex_util.
        url_encode(p_tms_id), p_http_method => 'POST', p_username => 'apex',
--,p_credential_static_id  => 'Credentials_for_tms_vacation'
         p_password => 'Mijdfsbfd$vsd43fsdf', p_parm_name => apex_string.string_to_table('MissionID'),
                                                    p_parm_value => apex_string.string_to_table(p_tms_id));
--if request success
-- Process the response from the API request.
        IF apex_web_service.g_status_code = 200 THEN
-- If the request is successful, update the deletion status.
            v_tms_id := CAST ( l_clob AS VARCHAR2 );
            UPDATE hrf_emp_permission_request
            SET
                delete_tms = 1
            WHERE
                request_id = p_request_id;

        END IF;
    -- Insert a log entry for the request.
        INSERT INTO tms_api_log (
            request_id,
            log,
            stat
        ) VALUES (
            p_request_id,
            l_clob,
            apex_web_service.g_status_code || ' - Permission'
        );

        COMMIT;
    EXCEPTION
        WHEN OTHERS THEN
            sqlerr := sqlerrm;
                -- Handle exceptions and log errors.
            INSERT INTO tms_api_log (
                request_id,
                log,
                stat
            ) VALUES (
                p_request_id,
                sqlerr,
                apex_web_service.g_status_code || ' - Permission'
            );

            COMMIT;
    END;

------------------------------------------------------------
-------------------------------------------------------------------END Permissions---------------------------------------------------

-------------------------------------------------------------------OVERTIME---------------------------------------------------
-- Upload TMS Overtimes Procedure
    PROCEDURE upload_tms_overtimes AS
     /*
    This procedure is responsible for processing and uploading overtime requests to the Time Management System (TMS).
    It iterates through eligible overtime records, sends the data to TMS, and updates the relevant status upon successful completion.
    */
        -- Cursor to retrieve eligible overtime requests for upload.
        CURSOR cr IS
        SELECT
            *
        FROM
            hrf_emp_overtime_request
        WHERE
                uploaded_tms = 0
            AND approved = 1
            AND tms_id IS NULL;

    BEGIN
        IF sys_context('userenv', 'server_host') <> 'apex' THEN
            RETURN;
        END IF;

        -- Iterate through eligible overtime requests and call the insert_tms_overtime function.
        FOR c IN cr LOOP
            -- Lock the row to prevent concurrent processing
            DECLARE
                v_lock_id NUMBER;
            BEGIN
                SELECT request_id
                INTO v_lock_id
                FROM hrf_emp_overtime_request
                WHERE request_id = c.request_id
                  AND uploaded_tms = 0
                  AND tms_id IS NULL
                FOR UPDATE NOWAIT;
            EXCEPTION
                WHEN OTHERS THEN
                    CONTINUE;
            END;
            insert_tms_overtime(p_date => c.overtime_date, p_from => c.from_hour, p_to => c.to_hour, p_emp_id => c.emp_id, p_request_id =>
            c.request_id,
                               p_desc => c.reason);
        END LOOP;
    END;
------------------------------------------------------------
-- Delete TMS Overtimes Procedure
    PROCEDURE delete_tms_overtimes AS
      /*
    This procedure is responsible for deleting overtime records in the Time Management System (TMS).
    It iterates through eligible deletion requests, initiates deletion requests for each, and updates the status accordingly.
    */
        -- Cursor to retrieve eligible overtime requests for deletion.

        CURSOR cr IS
        SELECT
            *
        FROM
            hrf_emp_overtime_request
        WHERE
                delete_tms = 0
            AND delete_approved = 1
            AND tms_id IS NOT NULL;

    BEGIN
        IF sys_context('userenv', 'server_host') <> 'apex' THEN
            RETURN;
        END IF;

        -- Iterate through eligible overtime deletion requests and call the delete_tms_overtime function.
        FOR c IN cr LOOP
            delete_tms_overtime(p_tms_id => c.tms_id, p_request_id => c.request_id);
        END LOOP;
    END;
------------------------------------------------------------
-- Insert TMS Overtime Procedure
    PROCEDURE insert_tms_overtime (
        p_date       DATE,
        p_from       DATE,
        p_to         DATE,
        p_emp_id     VARCHAR2,
        p_request_id NUMBER,
        p_desc       VARCHAR2
    ) AS
    /*
    This procedure handles the insertion of overtime records into the Time Management System (TMS).
    It constructs a JSON-based REST API request with overtime details, sends the request to TMS,
    and processes the response, updating the status of the corresponding overtime request.
    */
        sqlerr   VARCHAR2(4000);
        v_tms_id VARCHAR2(99);
        l_clob   CLOB;
    BEGIN
        -- Set request headers for the REST API call.
        apex_web_service.g_request_headers.DELETE();
        apex_web_service.g_request_headers(1).name := 'Content-Type';
        apex_web_service.g_request_headers(1).value := 'application/json';
        l_clob := apex_web_service.make_rest_request(p_url => 'http://tms.eprom.com.eg:8091/ApprovedOvertime/add?Date='
                                                              || apex_util.url_encode(to_char(p_date, 'mm/dd/yyyy'))
                                                              || '&FromTime='
                                                              || apex_util.url_encode(to_char(p_from, 'mm/dd/yyyy hh24:mi'))
                                                              || '&ToTime='
                                                              || apex_util.url_encode(to_char(p_to, 'mm/dd/yyyy hh24:mi'))
                                                              || '&Description='
                                                              || utl_url.escape(url => p_desc, url_charset => 'AL32UTF8')
                                                              || '&EmployeeNumber='
                                                              || apex_util.url_encode(p_emp_id), p_http_method => 'POST', p_username =>
                                                              'apex',
--,p_credential_static_id  => 'Credentials_for_tms_vacation'
                                                               p_password => 'Mijdfsbfd$vsd43fsdf', p_parm_name => apex_string.string_to_table(
                                                              'ANY'), --any content
                                                    p_parm_value => apex_string.string_to_table('THING') --any content does not matter
                                                    );
    -- Process the response from the API request.
        IF apex_web_service.g_status_code = 200 THEN
                -- If the request is successful, update the uploaded status and TMS ID.
            v_tms_id := CAST ( l_clob AS VARCHAR2 );
            UPDATE hrf_emp_overtime_request
            SET
                uploaded_tms = 1,
                tms_id = v_tms_id
            WHERE
                request_id = p_request_id;

        ELSIF apex_web_service.g_status_code = 418 THEN
                -- If the request returns HTTP status code 418, update the approval status.
            UPDATE hrf_emp_overtime_request
            SET
                approved = 4
            WHERE
                request_id = p_request_id;
  --send notification
                central.xxapex_emp_notifications.add_notification(
                p_emp_id => p_emp_id,
                p_title => ' طلب ساعات اضافية ' ,
                p_body => 'تم الالغاء لتأخر المدير الاعتماد فى شهر الطلب',
                p_app_id => 104,
                p_page_id => 100,
                p_task_id => 'Request ID:'|| p_request_id,
                p_status => 3
                );
        END IF;
    -- Insert a log entry for the request.
        INSERT INTO tms_api_log (
            request_id,
            log,
            stat
        ) VALUES (
            p_request_id,
            l_clob,
            apex_web_service.g_status_code || ' - OVERTIME'
        );

        COMMIT;
    EXCEPTION
        WHEN OTHERS THEN
            sqlerr := sqlerrm;
                    -- Handle exceptions and log errors.
            INSERT INTO tms_api_log (
                request_id,
                log,
                stat
            ) VALUES (
                p_request_id,
                sqlerr,
                apex_web_service.g_status_code || ' - OVERTIME'
            );

            COMMIT;
    END;
------------------------------------------------------------
-- Delete TMS Overtime Procedure
    PROCEDURE delete_tms_overtime (
        p_tms_id     NUMBER,
        p_request_id NUMBER
    ) AS
        /*
    This procedure sends a request to delete an overtime record from the Time Management System (TMS).
    It processes the API response and updates the deletion status accordingly.
    */
        sqlerr   VARCHAR2(4000);
        v_tms_id VARCHAR2(99);
        l_clob   CLOB;
    BEGIN
        -- Set request headers for the REST API call.
        apex_web_service.g_request_headers.DELETE();
        apex_web_service.g_request_headers(1).name := 'Content-Type';
        apex_web_service.g_request_headers(1).value := 'application/json';
            -- Make a REST API request to delete an overtime record.
        l_clob := apex_web_service.make_rest_request(p_url => 'http://tms.eprom.com.eg:8091/ApprovedOvertime/delete?ApprovedOvertimeID=' ||
        apex_util.url_encode(p_tms_id), p_http_method => 'POST', p_username => 'apex',
--,p_credential_static_id  => 'Credentials_for_tms_vacation'
         p_password => 'Mijdfsbfd$vsd43fsdf', p_parm_name => apex_string.string_to_table('ApprovedOvertimeID'),
                                                    p_parm_value => apex_string.string_to_table(p_tms_id));
--if request success
-- Process the response from the API request.
        IF apex_web_service.g_status_code = 200 THEN
                -- If the request is successful, update the deletion status.
            v_tms_id := CAST ( l_clob AS VARCHAR2 );
            UPDATE hrf_emp_overtime_request
            SET
                delete_tms = 1
            WHERE
                request_id = p_request_id;

        END IF;
--insert request log
    -- Insert a log entry for the request.
        INSERT INTO tms_api_log (
            request_id,
            log,
            stat
        ) VALUES (
            p_request_id,
            l_clob,
            apex_web_service.g_status_code || ' - OVERTIME'
        );

        COMMIT;
    EXCEPTION
        WHEN OTHERS THEN
            sqlerr := sqlerrm;
                    -- Handle exceptions and log errors.
            INSERT INTO tms_api_log (
                request_id,
                log,
                stat
            ) VALUES (
                p_request_id,
                sqlerr,
                apex_web_service.g_status_code || ' - OVERTIME'
            );

            COMMIT;
    END;

------------------------------------------------------------
-------------------------------------------------------------------END OVERTIME---------------------------------------------------

-------------------------------------------------------------------OTHER FUNCTIONS ---------------------------------------------------
-- in_holiday Function
-- Determines if a given date falls within a holiday period.
-- Params:
-- p_date: The date to check for being a holiday.
-- Returns:
-- A boolean value - true if the date is a holiday, false otherwise.

    FUNCTION in_holiday (
        p_date DATE
    ) RETURN BOOLEAN AS
        v_count NUMBER := 0;
    BEGIN
        -- Query the count of holidays that cover the given date.

        SELECT
            COUNT(*)
        INTO v_count
        FROM
            central.xxapex_eprom_holiday
        WHERE
            trunc(p_date) = trunc(HOLIDAY_DATE);

    -- If there are matching holidays, return true; otherwise, return false.
        IF v_count > 0 THEN
            RETURN true;
        END IF;
        RETURN false;
    END;
--------------------------------------------------

-- get_cut_date Function
-- Retrieves the cut-off date for a given location and date.
-- Params:
-- p_date: The reference date.
-- p_location: The location code for which to fetch the cut-off date.
-- Returns:
-- The cut-off date for the specified location and date, or NULL if not found.

    FUNCTION get_cut_date (
        p_date     DATE,
        p_location VARCHAR
    ) RETURN DATE AS
        v_cut_date DATE;
    BEGIN
        -- Query the cut-off date based on the year, month, and location.

        SELECT
            cutdate
        INTO v_cut_date
        FROM
            tms_cut_dates
        WHERE
                year = year(p_date)
            AND month = mon(p_date)
            AND locationid = (
                SELECT
                    tms_id
                FROM
                    tms_location_map
                WHERE
                    site_code = p_location
            );
    -- If a cut-off date is found, return it; otherwise, return NULL in case of no data found.
        RETURN v_cut_date;
    EXCEPTION
        WHEN no_data_found THEN
                -- Handle exceptions by returning NULL when no data is found.
            RETURN NULL;
    END get_cut_date;


-------------------------------------------------------------------END OTHER FUNCTIONS ---------------------------------------------------

END tms_api;
/
