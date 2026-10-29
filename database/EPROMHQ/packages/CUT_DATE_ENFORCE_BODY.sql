
  CREATE OR REPLACE EDITIONABLE PACKAGE BODY "EPROMHQ"."CUT_DATE_ENFORCE" AS
-------------------------------------------------------------------------------------------------------------
    CURSOR cut_cr IS
    SELECT
        cd.cutdate,
        lm.site_code,
        year,
        month
    FROM
             tms_cut_dates cd
        JOIN tms_location_map lm ON cd.locationid = lm.tms_id
    WHERE
            cd.month >= mon(sysdate - 45)
        AND cd.year >= year(sysdate - 45);

-------------------------------------------------------------------------------------------------------------

    PROCEDURE enforce_cut_date_leave AS

        CURSOR leave_cursor (
            cp_site     VARCHAR,
            cp_year     NUMBER,
            cp_month    NUMBER,
            cp_cut_date DATE
        ) IS
        SELECT
            *
        FROM
                 hrf_emp_leave_request r
            JOIN central.xxapex_hr_emp_data e ON e.emp_number = r.emp_id
                                                 AND e.site_code = cp_site
        WHERE
                1 = 1
            AND ( ( r.approved IN ( 0, 1 )
                    AND r.tms_id IS NULL )
                  OR ( r.delete_approved IN ( 0, 1 )
                       AND r.delete_tms IS NULL ) )
            AND year(r.from_date) <= cp_year
            AND mon(r.from_date) <= cp_month
            AND ( cp_cut_date < sysdate
                  AND r.from_date < cp_cut_date );

        v_task_id VARCHAR2(99);
        v_title   VARCHAR2(99);
    BEGIN
    -----start cut date cursor
        FOR cc IN cut_cr LOOP
  ---------------leaves cursor --------------------------------------------
  --create a session so we can cancel task
            apex_session.create_session(p_app_id => 115, p_page_id => 1, p_username => '1825' --task admin
            );

            FOR lc IN leave_cursor(cc.site_code, cc.year, cc.month, cc.cutdate) LOOP
                v_task_id := central.get_last_string(lc.task_ids, '->');
                IF lc.delete_approved = 1 OR lc.approved = 1 THEN  --delete approved but not deleted on tms --aproved not send to tms
                    NULL;
                ELSIF lc.approved = 1 THEN --aproved not send to tms
                    NULL;
                ELSIF lc.delete_approved = 0 OR lc.approved = 0 THEN -- not yet approved
  --cancel task
                    BEGIN
                        NULL;
    -- may does not work here !!!!!!!!!!!!!!! ==>put also  in page 300 in 104 via btn
                        apex_approval.cancel_task(p_task_id => v_task_id);

    --sometimes it fails if task is too old
                    EXCEPTION
                        WHEN OTHERS THEN
                            NULL;
                    END;
                END IF;

-------------------------------------------
         IF lc.approved IN (0, 1) AND lc.LEAVE_TYPE = 'H' THEN
    v_title := 'طلب اجازة سنوية';
            ELSIF lc.approved IN (0, 1) AND lc.LEAVE_TYPE = 'C' THEN
    v_title := 'طلب اجازة عارضة';
            ELSIF lc.approved IN (0, 1) AND lc.LEAVE_TYPE = 'RH' THEN
    v_title := 'طلب اجازة ساعات راحة';
    -- Set approved = 4
                    UPDATE hrf_emp_leave_request
                    SET
                        approved = 4
                    WHERE
                        request_id = lc.request_id;
                END IF;

----------------------------------------------
         IF lc.delete_approved IN (0, 1) AND lc.LEAVE_TYPE = 'H' THEN
    v_title := '   طلب الغاء اجازة سنوية';
ELSIF lc.delete_approved IN (0, 1) AND lc.LEAVE_TYPE = 'C' THEN
    v_title := 'طلب الغاء اجازة عارضة';
ELSIF lc.delete_approved IN (0, 1) AND lc.LEAVE_TYPE = 'RH' THEN
    v_title := 'طلب الغاء اجازة ساعات راحة';
    --set delete_approved = 4
                    UPDATE hrf_emp_leave_request
                    SET
                        delete_approved = 4
                    WHERE
                        request_id = lc.request_id;

                END IF;
------------------------------------------------
                COMMIT;

  --send notification
                central.xxapex_emp_notifications.add_notification(
                p_emp_id => lc.emp_id,
                p_title => v_title,
                p_body => 'تم الالغاء لتأخر المدير الاعتماد فى شهر الطلب',
                p_app_id => 104,
                p_page_id => 100,
                p_task_id => v_task_id,
                p_status => 3
                );

            END LOOP;
  --------------- end leaves cursor --------------------------------------------
        END LOOP;
        --------end cut date cursor
    END enforce_cut_date_leave;
-------------------------------------------------------------------------------------------------------------
    PROCEDURE enforce_cut_date_permission AS

        CURSOR perm_cursor (
            cp_site     VARCHAR,
            cp_year     NUMBER,
            cp_month    NUMBER,
            cp_cut_date DATE
        ) IS
        SELECT
            *
        FROM
                 HRF_EMP_PERMISSION_REQUEST r
            JOIN central.xxapex_hr_emp_data e ON e.emp_number = r.emp_id
                                                 AND e.site_code = cp_site
        WHERE
                1 = 1
            AND ( ( r.approved IN ( 0, 1 )
                    AND r.tms_id IS NULL )
                  OR ( r.delete_approved IN ( 0, 1 )
                       AND r.delete_tms IS NULL ) )
            AND year(r.PERMISSION_DATE) <= cp_year
            AND mon(r.PERMISSION_DATE) <= cp_month
            AND ( cp_cut_date < sysdate
                  AND r.PERMISSION_DATE < cp_cut_date );

        v_task_id VARCHAR2(99);
        v_title   VARCHAR2(99);
    BEGIN
    -----start cut date cursor
        FOR cc IN cut_cr LOOP
  ---------------perm cursor --------------------------------------------
  --create a session so we can cancel task
            apex_session.create_session(p_app_id => 115, p_page_id => 1, p_username => '1825' --task admin
            );

            FOR lc IN perm_cursor(cc.site_code, cc.year, cc.month, cc.cutdate) LOOP
                v_task_id := central.get_last_string(lc.task_ids, '->');
                IF lc.delete_approved = 1 OR lc.approved = 1 THEN  --delete approved but not deleted on tms --aproved not send to tms
                    NULL;
                ELSIF lc.approved = 1 THEN --aproved not send to tms
                    NULL;
                ELSIF lc.delete_approved = 0 OR lc.approved = 0 THEN -- not yet approved
  --cancel task
                    BEGIN
                        NULL;
    -- may does not work here !!!!!!!!!!!!!!! ==>put also  in page 300 in 104 via btn
                        apex_approval.cancel_task(p_task_id => v_task_id);

    --sometimes it fails if task is too old
                    EXCEPTION
                        WHEN OTHERS THEN
                            NULL;
                    END;
                END IF;

             IF lc.approved IN ( 0, 1 ) and lc.PERMISSION_TYPE = 'PP' THEN
                    v_title := ' طلب اذن شخصي';
                ELSIF lc.approved in (0,1) and lc.PERMISSION_TYPE = 'CP' THEN
                    v_title := ' طلب اذن عمل';
    --set approved = 4
                    UPDATE HRF_EMP_PERMISSION_REQUEST
                    SET
                        approved = 4
                    WHERE
                        request_id = lc.request_id;

                END IF;

                IF lc.delete_approved IN ( 0, 1 ) and lc.PERMISSION_TYPE = 'PP' THEN
                    v_title := ' طلب الغاء اذن شخصي';
                ELSIF lc.delete_approved in (0,1) and lc.PERMISSION_TYPE = 'CP' THEN
                    v_title := 'طلب الغاء اذن عمل';
    --set delete_approved = 4
                    UPDATE HRF_EMP_PERMISSION_REQUEST
                    SET
                        delete_approved = 4
                    WHERE
                        request_id = lc.request_id;

                END IF;

                COMMIT;

--  send notification
                central.xxapex_emp_notifications.add_notification(p_emp_id => lc.emp_id,
                p_title => v_title, p_body => 'تم الالغاء لتأخر المدير الاعتماد فى شهر الطلب',
                p_app_id => 104, p_page_id => 100,
                p_task_id => v_task_id, p_status => 3);

            END LOOP;
  --------------- end leaves cursor --------------------------------------------
        END LOOP;
        --------end cut date cursor
    END enforce_cut_date_permission;
-------------------------------------------------------------------------------------------------------------
    PROCEDURE enforce_cut_date_mission AS
   CURSOR miss_cursor (
            cp_site     VARCHAR,
            cp_year     NUMBER,
            cp_month    NUMBER,
            cp_cut_date DATE
        ) IS
        SELECT
            *
        FROM
                 HRF_EMP_mission_REQUEST r
            JOIN central.xxapex_hr_emp_data e ON e.emp_number = r.emp_id
                                                 AND e.site_code = cp_site
        WHERE
                1 = 1
            AND ( ( r.approved IN ( 0, 1 )
                    AND r.tms_id IS NULL )
                  OR ( r.delete_approved IN ( 0, 1 )
                       AND r.delete_tms IS NULL ) )
            AND year(r.FROM_DATE) <= cp_year
            AND mon(r.FROM_DATE) <= cp_month
            AND ( cp_cut_date < sysdate
                  AND r.FROM_DATE < cp_cut_date );

        v_task_id VARCHAR2(99);
        v_title   VARCHAR2(99);
    BEGIN
    -----start cut date cursor
        FOR cc IN cut_cr LOOP
  ---------------perm cursor --------------------------------------------
  --create a session so we can cancel task
            apex_session.create_session(p_app_id => 115, p_page_id => 1, p_username => '1825' --task admin
            );

            FOR lc IN miss_cursor(cc.site_code, cc.year, cc.month, cc.cutdate) LOOP
                v_task_id := central.get_last_string(lc.task_ids, '->');
                IF lc.delete_approved = 1 OR lc.approved = 1 THEN  --delete approved but not deleted on tms --aproved not send to tms
                    NULL;
                ELSIF lc.approved = 1 THEN --aproved not send to tms
                    NULL;
                ELSIF lc.delete_approved = 0 OR lc.approved = 0 THEN -- not yet approved
  --cancel task
                    BEGIN
                        NULL;
    -- may does not work here !!!!!!!!!!!!!!! ==>put also  in page 300 in 104 via btn
                        apex_approval.cancel_task(p_task_id => v_task_id);

    --sometimes it fails if task is too old
                    EXCEPTION
                        WHEN OTHERS THEN
                            NULL;
                    END;
                END IF;

            IF lc.approved IN (0, 1) AND lc.REQUEST_TYPE_ID = '72' THEN
                 v_title := 'طلب مهمه عمل';
            ELSIF lc.approved IN (0, 1) AND lc.REQUEST_TYPE_ID = '121' THEN
                 v_title := 'طلب مهمة تدريبية ';

    --set approved = 4
                    UPDATE HRF_EMP_mission_REQUEST
                    SET
                        Approved = 4
                    WHERE
                        Request_id = lc.request_id;

                END IF;

                IF lc.delete_approved IN ( 0, 1 ) AND lc.REQUEST_TYPE_ID = '72' THEN
                    v_title := 'طلب الغاء مهمه عمل';
                ELSIF lc.delete_approved IN (0, 1) AND lc.REQUEST_TYPE_ID = '121' THEN
                 v_title := 'طلب الغاء مهمة تدريبية ';

    --set delete_approved = 4
                    UPDATE HRF_EMP_mission_REQUEST
                    SET
                        delete_approved = 4
                    WHERE
                        request_id = lc.request_id;

                END IF;

                COMMIT;

--  send notification
                central.xxapex_emp_notifications.add_notification(p_emp_id => lc.emp_id,
                p_title => v_title, p_body => 'تم الالغاء لتأخر المدير الاعتماد فى شهر الطلب',
                p_app_id => 104, p_page_id => 100,
                p_task_id => v_task_id, p_status => 3);

            END LOOP;
  --------------- end miss cursor --------------------------------------------
        END LOOP;
        --------end cut date cursor
    END enforce_cut_date_mission;
-------------------------------------------------------------------------------------------------------------
    PROCEDURE enforce_cut_date_overtime AS
    BEGIN
    -- TODO: Implementation required for PROCEDURE CUT_DATE_ENFORCE.ENFORCE_CUT_DATE_overtime
        NULL;
    END enforce_cut_date_overtime;
-------------------------------------------------------------------------------------------------------------
END cut_date_enforce;
/
