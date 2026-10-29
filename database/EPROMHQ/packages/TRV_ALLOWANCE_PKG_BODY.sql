
  CREATE OR REPLACE EDITIONABLE PACKAGE BODY "EPROMHQ"."TRV_ALLOWANCE_PKG" AS
    /* =========================================================================
       Package Body: epromhq.trv_allowance_pkg
       ========================================================================= */

    -- -------------------------------------------------------------------------
    -- Page Initialization / Defaults
    -- -------------------------------------------------------------------------
    PROCEDURE init_page_defaults (
        p_app_user     IN VARCHAR2,
        p_tra_emp_num  IN OUT VARCHAR2,
        p_emp_number   OUT VARCHAR2,
        p_emp_id       OUT VARCHAR2
    ) IS
    BEGIN
        p_tra_emp_num := NVL(p_tra_emp_num, p_app_user);
        p_emp_number  := p_tra_emp_num;
        p_emp_id      := p_tra_emp_num;
    END init_page_defaults;

    -- -------------------------------------------------------------------------
    -- Helper: Robust Date Parser
    -- -------------------------------------------------------------------------
    FUNCTION parse_date (
        p_date_str IN VARCHAR2
    ) RETURN DATE IS
        v_clean VARCHAR2(100);
    BEGIN
        IF p_date_str IS NULL OR TRIM(p_date_str) IS NULL THEN
            RETURN NULL;
        END IF;

        v_clean := TRIM(p_date_str);

        -- 1. Try standard ISO date prefix (YYYY-MM-DD)
        IF LENGTH(v_clean) >= 10 AND SUBSTR(v_clean, 5, 1) = '-' AND SUBSTR(v_clean, 8, 1) = '-' THEN
            BEGIN
                RETURN TO_DATE(SUBSTR(v_clean, 1, 10), 'YYYY-MM-DD');
            EXCEPTION
                WHEN OTHERS THEN NULL;
            END;
        END IF;

        -- 2. Try standard Oracle DD-MON-RRRR / DD-MON-YYYY
        BEGIN
            RETURN TO_DATE(v_clean, 'DD-MON-RRRR');
        EXCEPTION
            WHEN OTHERS THEN NULL;
        END;

        -- 3. Fallback to default session NLS
        BEGIN
            RETURN TO_DATE(v_clean);
        EXCEPTION
            WHEN OTHERS THEN
                RAISE_APPLICATION_ERROR(-20002, 'صيغة التاريخ غير صحيحة: ' || p_date_str);
        END;
    END parse_date;

    -- -------------------------------------------------------------------------
    -- Validation: Dates
    -- -------------------------------------------------------------------------
    FUNCTION validate_dates (
        p_request_type_id IN VARCHAR2,
        p_return_same_day IN VARCHAR2,
        p_date_from_str   IN VARCHAR2,
        p_date_to_str     IN VARCHAR2
    ) RETURN VARCHAR2 IS
        v_date_from DATE;
        v_date_to   DATE;
    BEGIN
        -- External travel (47) with hotel stay (return_same_day <> 1) requires both dates
        IF p_request_type_id = c_req_type_external AND NVL(p_return_same_day, '0') <> '1' THEN
            IF p_date_from_str IS NULL OR TRIM(p_date_from_str) IS NULL OR
               p_date_to_str   IS NULL OR TRIM(p_date_to_str)   IS NULL THEN
                RETURN 'من فضلك أدخل تاريخ البداية وتاريخ النهاية أولاً';
            END IF;
        END IF;

        -- Parse dates if provided
        IF p_date_from_str IS NOT NULL AND TRIM(p_date_from_str) IS NOT NULL THEN
            v_date_from := parse_date(p_date_from_str);
        END IF;

        IF p_date_to_str IS NOT NULL AND TRIM(p_date_to_str) IS NOT NULL THEN
            v_date_to := parse_date(p_date_to_str);
        END IF;

        -- Chronological sequence check
        IF v_date_from IS NOT NULL AND v_date_to IS NOT NULL THEN
            IF NVL(p_return_same_day, '0') = '1' THEN
                IF v_date_from > v_date_to THEN
                    RETURN 'تاريخ البداية لا يمكن أن يكون بعد تاريخ النهاية.';
                END IF;
            ELSE
                IF p_request_type_id = c_req_type_external THEN
                    IF v_date_from >= v_date_to THEN
                        RETURN 'تاريخ النهاية يجب أن يكون بعد تاريخ البداية بيوم واحد على الأقل.';
                    END IF;
                ELSE
                    IF v_date_from > v_date_to THEN
                        RETURN 'تاريخ البداية لا يمكن أن يكون بعد تاريخ النهاية.';
                    END IF;
                END IF;
            END IF;
        END IF;

        -- Retroactive requirement: travel cannot be submitted before end date
        IF v_date_to IS NOT NULL AND TRUNC(v_date_to) > TRUNC(SYSDATE) THEN
            RETURN 'لا يمكنك تقديم الطلب قبل انتهاء مدته';
        END IF;

        RETURN NULL;
    EXCEPTION
        WHEN OTHERS THEN
            RETURN 'خطأ في التحقق من التواريخ: ' || SQLERRM;
    END validate_dates;

    -- -------------------------------------------------------------------------
    -- Validation: Overlapping Requests
    -- -------------------------------------------------------------------------
    FUNCTION validate_overlap (
        p_emp_id          IN VARCHAR2,
        p_request_type_id IN VARCHAR2,
        p_date_from       IN DATE,
        p_date_to         IN DATE,
        p_request_id      IN NUMBER DEFAULT NULL
    ) RETURN VARCHAR2 IS
        l_count NUMBER := 0;
    BEGIN
        IF p_emp_id IS NULL OR p_date_from IS NULL OR p_date_to IS NULL THEN
            RETURN NULL;
        END IF;

        SELECT COUNT(*)
          INTO l_count
          FROM epromhq.trv_allowance a
         WHERE a.emp_id = p_emp_id
           AND NVL(a.request_type_id, '0') = NVL(p_request_type_id, NVL(a.request_type_id, '0'))
           AND NVL(a.approval_manager, 'PENDING') <> '0'
           AND NVL(a.approval_hotel, 'PENDING')   <> '0'
           AND NVL(a.approval_finance, 'PENDING') <> '0'
           AND NVL(a.status, 'DRAFT') NOT IN ('TERMINATED', 'REJECTED', 'DELETED')
           AND NVL(a.delete_approval_car, 0)     = 0
           AND NVL(a.delete_approval_hotel, 0)   = 0
           AND NVL(a.delete_approval_finance, 0) = 0
           AND TRUNC(p_date_from) <= TRUNC(a.date_to)
           AND TRUNC(p_date_to)   >= TRUNC(a.date_from)
           AND (p_request_id IS NULL OR a.request_id <> p_request_id);

        IF l_count > 0 THEN
            RETURN 'يوجد طلب آخر لنفس الفترة أو يوجد تقاطع مع Request سابق.';
        END IF;

        RETURN NULL;
    EXCEPTION
        WHEN OTHERS THEN
            RETURN 'خطأ في التحقق من عدم التكرار: ' || SQLERRM;
    END validate_overlap;

    -- -------------------------------------------------------------------------
    -- Validation: Hotel Nights Count
    -- -------------------------------------------------------------------------
    FUNCTION validate_hotel_nights (
        p_request_type_id IN VARCHAR2,
        p_return_same_day IN VARCHAR2,
        p_date_from       IN DATE,
        p_date_to         IN DATE,
        p_hotels_json     IN CLOB
    ) RETURN VARCHAR2 IS
        l_total_days  NUMBER := 0;
        l_max_allowed NUMBER := 0;
    BEGIN
        -- Hotel validation only applies to external travel not returning same day
        IF p_request_type_id <> c_req_type_external OR NVL(p_return_same_day, '0') = '1' THEN
            RETURN NULL;
        END IF;

        IF p_date_from IS NULL OR p_date_to IS NULL THEN
            RETURN 'من فضلك أدخل تاريخ البداية وتاريخ النهاية أولاً';
        END IF;

        l_max_allowed := TRUNC(p_date_to) - TRUNC(p_date_from);
        IF l_max_allowed < 0 THEN
            RETURN 'تاريخ النهاية يجب أن يكون أكبر من تاريخ البداية';
        END IF;

        IF p_hotels_json IS NULL OR TRIM(p_hotels_json) IS NULL THEN
            RETURN NULL;
        END IF;

        SELECT NVL(SUM(NVL(days, 0)), 0)
          INTO l_total_days
          FROM JSON_TABLE(
                 p_hotels_json,
                 '$[*]'
                 COLUMNS (
                   days NUMBER PATH '$.days'
                 )
               );

        IF l_total_days > l_max_allowed THEN
            RETURN 'إجمالي ليالي الإقامة (' || l_total_days ||
                   ') لا يجوز أن يتجاوز مدة الرحلة (' || l_max_allowed || ' ليلة)';
        END IF;

        RETURN NULL;
    EXCEPTION
        WHEN OTHERS THEN
            RETURN 'خطأ في التحقق من بيانات الإقامة: ' || SQLERRM;
    END validate_hotel_nights;

    -- -------------------------------------------------------------------------
    -- Validation: Hotels JSON Data Integrity
    -- -------------------------------------------------------------------------
    FUNCTION validate_hotels_json (
        p_request_type_id IN VARCHAR2,
        p_return_same_day IN VARCHAR2,
        p_hotels_json     IN CLOB
    ) RETURN VARCHAR2 IS
        l_invalid_count NUMBER := 0;
        l_total_count   NUMBER := 0;
    BEGIN
        IF p_request_type_id <> c_req_type_external OR NVL(p_return_same_day, '0') = '1' THEN
            RETURN NULL;
        END IF;

        IF p_hotels_json IS NULL OR TRIM(p_hotels_json) IS NULL THEN
            RETURN NULL;
        END IF;

        SELECT COUNT(*),
               COUNT(CASE WHEN NVL(TRIM(hotel_type), 'X') = 'X' OR days IS NULL OR days <= 0 THEN 1 END)
          INTO l_total_count,
               l_invalid_count
          FROM JSON_TABLE(
                 p_hotels_json,
                 '$[*]'
                 COLUMNS (
                   hotel_type VARCHAR2(50) PATH '$.hotel_type',
                   days       NUMBER       PATH '$.days'
                 )
               );

        IF l_invalid_count > 0 THEN
            RETURN 'من فضلك أدخل جميع بيانات الإقامة بشكل صحيح (نوع الفندق وعدد الليالي أكبر من صفر).';
        END IF;

        RETURN NULL;
    EXCEPTION
        WHEN OTHERS THEN
            RETURN 'خطأ في التحقق من جدول الفنادق: ' || SQLERRM;
    END validate_hotels_json;

    -- -------------------------------------------------------------------------
    -- Validation: Lines JSON Data Integrity
    -- -------------------------------------------------------------------------
    FUNCTION validate_lines_json (
        p_lines_json IN CLOB
    ) RETURN VARCHAR2 IS
        l_total_count   NUMBER := 0;
        l_invalid_count NUMBER := 0;
    BEGIN
        IF p_lines_json IS NULL OR TRIM(p_lines_json) IS NULL THEN
            RETURN 'يجب إدخال بيانات الإنتقالات اليومية.';
        END IF;

        SELECT COUNT(*),
               COUNT(CASE
                       WHEN trip_date IS NULL OR TRIM(trip_date) IS NULL
                         OR description IS NULL OR TRIM(description) IS NULL
                         OR transport_type IS NULL OR TRIM(transport_type) IS NULL
                       THEN 1
                     END)
          INTO l_total_count,
               l_invalid_count
          FROM JSON_TABLE(
                 p_lines_json,
                 '$[*]'
                 COLUMNS (
                   trip_date      VARCHAR2(50)   PATH '$.trip_date',
                   description    VARCHAR2(4000) PATH '$.description',
                   transport_type VARCHAR2(200)  PATH '$.transport_type',
                   cost           NUMBER         PATH '$.cost'
                 )
               );

        IF l_total_count = 0 THEN
            RETURN 'يجب إدخال حركة انتقال واحدة على الأقل.';
        END IF;

        IF l_invalid_count > 0 THEN
            RETURN 'من فضلك استكمل جميع بيانات حركات الانتقال (التاريخ، الوصف، نوع الانتقال).';
        END IF;

        RETURN NULL;
    EXCEPTION
        WHEN OTHERS THEN
            RETURN 'خطأ في التحقق من بيانات حركات الانتقال: ' || SQLERRM;
    END validate_lines_json;

    -- -------------------------------------------------------------------------
    -- Validation: Configured Approvers Guard
    -- -------------------------------------------------------------------------
    FUNCTION validate_approvers (
        p_emp_id          IN VARCHAR2,
        p_request_type_id IN VARCHAR2
    ) RETURN VARCHAR2 IS
        l_approver_count NUMBER := 0;
    BEGIN
        IF p_emp_id IS NULL OR p_request_type_id IS NULL THEN
            RETURN NULL;
        END IF;

        SELECT COUNT(*)
          INTO l_approver_count
          FROM central.apr_approval_result_v
         WHERE emp_number = p_emp_id
           AND request_type_id = TO_NUMBER(p_request_type_id)
           AND approve_type = 'FYA'
           AND approver IS NOT NULL;

        IF l_approver_count = 0 THEN
            RETURN 'لا يمكنك تقديم الطلب لعدم وجود معتمدين محددين لك في النظام لهذا النوع من الطلبات. يرجى مراجعة إدارة الموارد البشرية لتحديد مسار الاعتماد أولاً.';
        END IF;

        RETURN NULL;
    EXCEPTION
        WHEN OTHERS THEN
            RETURN 'خطأ أثناء التحقق من مسار الاعتماد: ' || SQLERRM;
    END validate_approvers;

    -- -------------------------------------------------------------------------
    -- Master Validation (Option A: Single Entry Point for APEX Page 94)
    -- -------------------------------------------------------------------------
    FUNCTION validate_request (
        p_emp_id          IN VARCHAR2,
        p_request_type_id IN VARCHAR2,
        p_return_same_day IN VARCHAR2,
        p_date_from_str   IN VARCHAR2,
        p_date_to_str     IN VARCHAR2,
        p_lines_json      IN CLOB,
        p_hotels_json     IN CLOB,
        p_request_id      IN NUMBER DEFAULT NULL
    ) RETURN VARCHAR2 IS
        v_err       VARCHAR2(4000);
        v_date_from DATE;
        v_date_to   DATE;
    BEGIN
        -- 0. Validate approver configuration guard
        v_err := validate_approvers(
            p_emp_id          => p_emp_id,
            p_request_type_id => p_request_type_id
        );
        IF v_err IS NOT NULL THEN
            RETURN v_err;
        END IF;

        -- 1. Validate date logic & retroactive submission
        v_err := validate_dates(
            p_request_type_id => p_request_type_id,
            p_return_same_day => p_return_same_day,
            p_date_from_str   => p_date_from_str,
            p_date_to_str     => p_date_to_str
        );
        IF v_err IS NOT NULL THEN
            RETURN v_err;
        END IF;

        -- Parse dates for subsequent checks
        IF p_date_from_str IS NOT NULL AND TRIM(p_date_from_str) IS NOT NULL THEN
            v_date_from := parse_date(p_date_from_str);
        END IF;
        IF p_date_to_str IS NOT NULL AND TRIM(p_date_to_str) IS NOT NULL THEN
            v_date_to := parse_date(p_date_to_str);
        END IF;

        -- 2. Validate travel movement lines
        v_err := validate_lines_json(p_lines_json => p_lines_json);
        IF v_err IS NOT NULL THEN
            RETURN v_err;
        END IF;

        -- 3. Validate hotel stays (if applicable)
        IF p_request_type_id = c_req_type_external AND NVL(p_return_same_day, '0') <> '1' THEN
            v_err := validate_hotels_json(
                p_request_type_id => p_request_type_id,
                p_return_same_day => p_return_same_day,
                p_hotels_json     => p_hotels_json
            );
            IF v_err IS NOT NULL THEN
                RETURN v_err;
            END IF;

            v_err := validate_hotel_nights(
                p_request_type_id => p_request_type_id,
                p_return_same_day => p_return_same_day,
                p_date_from       => v_date_from,
                p_date_to         => v_date_to,
                p_hotels_json     => p_hotels_json
            );
            IF v_err IS NOT NULL THEN
                RETURN v_err;
            END IF;
        END IF;

        -- 4. Validate overlap against existing active requests
        IF v_date_from IS NOT NULL AND v_date_to IS NOT NULL THEN
            v_err := validate_overlap(
                p_emp_id          => p_emp_id,
                p_request_type_id => p_request_type_id,
                p_date_from       => v_date_from,
                p_date_to         => v_date_to,
                p_request_id      => p_request_id
            );
            IF v_err IS NOT NULL THEN
                RETURN v_err;
            END IF;
        END IF;

        RETURN NULL; -- All checks passed
    END validate_request;

    -- -------------------------------------------------------------------------
    -- Transactional Processing: save_request
    -- -------------------------------------------------------------------------
    PROCEDURE save_request (
        p_emp_id               IN VARCHAR2,
        p_request_type_id      IN VARCHAR2,
        p_return_same_day      IN VARCHAR2,
        p_trip_purpose         IN VARCHAR2,
        p_trip_location        IN VARCHAR2,
        p_trip_location_other  IN VARCHAR2,
        p_date_from_str        IN VARCHAR2,
        p_start_time           IN VARCHAR2,
        p_date_to_str          IN VARCHAR2,
        p_end_time             IN VARCHAR2,
        p_lines_json           IN CLOB,
        p_hotels_json          IN CLOB,
        p_file_names           IN VARCHAR2,
        p_task_ids             IN VARCHAR2,
        x_request_id           OUT NUMBER
    ) IS
        v_date_from   DATE;
        v_date_to     DATE;
        v_user        VARCHAR2(100);
        v_location    VARCHAR2(150);
        v_err_msg     VARCHAR2(4000);
    BEGIN
        v_user := COALESCE(p_emp_id, SYS_CONTEXT('APEX$SESSION', 'APP_USER'), USER);

        -- Parse dates safely
        IF p_date_from_str IS NOT NULL AND TRIM(p_date_from_str) IS NOT NULL THEN
            v_date_from := parse_date(p_date_from_str);
        END IF;

        IF p_date_to_str IS NOT NULL AND TRIM(p_date_to_str) IS NOT NULL THEN
            v_date_to := parse_date(p_date_to_str);
        END IF;

        v_location := SUBSTR(TRIM(p_trip_location || ' ' || p_trip_location_other), 1, 150);

        -- 1. Insert Request Header
        INSERT INTO epromhq.trv_allowance (
            emp_id,
            trip_purpose,
            trip_location,
            date_from,
            start_time,
            date_to,
            end_time,
            created_by,
            request_type_id,
            return_same_day,
            status
        ) VALUES (
            v_user,
            p_trip_purpose,
            v_location,
            v_date_from,
            p_start_time,
            v_date_to,
            p_end_time,
            v_user,
            p_request_type_id,
            NVL(p_return_same_day, '0'),
            'DRAFT'
        ) RETURNING request_id INTO x_request_id;

        -- 2. Ingest Travel Movement Lines from JSON
        IF p_lines_json IS NOT NULL AND TRIM(p_lines_json) IS NOT NULL THEN
            FOR r IN (
                SELECT
                    CASE
                        WHEN jt.trip_date IS NULL OR TRIM(jt.trip_date) IS NULL THEN NULL
                        ELSE parse_date(jt.trip_date)
                    END AS date_from,
                    jt.description AS location_from,
                    jt.transport_type AS type_of_trans,
                    NVL(jt.cost, 0) AS amount
                FROM JSON_TABLE(
                    p_lines_json,
                    '$[*]'
                    COLUMNS (
                        trip_date      VARCHAR2(30)   PATH '$.trip_date',
                        description    VARCHAR2(500)  PATH '$.description',
                        transport_type VARCHAR2(50)   PATH '$.transport_type',
                        cost           NUMBER         PATH '$.cost'
                    )
                ) jt
            ) LOOP
                IF r.date_from IS NOT NULL OR r.location_from IS NOT NULL OR r.type_of_trans IS NOT NULL THEN
                    INSERT INTO epromhq.trv_expense (
                        request_id,
                        type_of_trans,
                        location_from,
                        amount,
                        date_from
                    ) VALUES (
                        x_request_id,
                        r.type_of_trans,
                        r.location_from,
                        r.amount,
                        r.date_from
                    );
                END IF;
            END LOOP;
        END IF;

        -- 3. Ingest Hotel Accommodations from JSON
        IF p_hotels_json IS NOT NULL AND TRIM(p_hotels_json) IS NOT NULL THEN
            DELETE FROM epromhq.trv_allowance_hotels
             WHERE request_id = x_request_id;

            FOR r IN (
                SELECT jt.hotel_type,
                       jt.days
                  FROM JSON_TABLE(
                      p_hotels_json,
                      '$[*]'
                      COLUMNS (
                          hotel_type VARCHAR2(20) PATH '$.hotel_type',
                          days       VARCHAR2(20) PATH '$.days'
                      )
                  ) jt
            ) LOOP
                IF TRIM(r.hotel_type) IS NOT NULL OR TRIM(r.days) IS NOT NULL THEN
                    INSERT INTO epromhq.trv_allowance_hotels (
                        request_id,
                        type_of_hotel,
                        number_of_days,
                        created_by
                    ) VALUES (
                        x_request_id,
                        r.hotel_type,
                        r.days,
                        v_user
                    );
                END IF;
            END LOOP;
        END IF;

        -- 4. Copy Uploaded Attachments from Temporary Storage
        IF p_file_names IS NOT NULL AND TRIM(p_file_names) IS NOT NULL THEN
            FOR file_rec IN (
                SELECT blob_content, filename, mime_type
                  FROM apex_application_temp_files
                 WHERE name IN (
                     SELECT column_value
                       FROM apex_string.split(p_file_names, ':')
                 )
            ) LOOP
                INSERT INTO epromhq.trv_attachment (
                    attach_name,
                    mime_type,
                    file_blob,
                    file_name,
                    request_id,
                    created_at,
                    updated_at
                ) VALUES (
                    file_rec.filename,
                    file_rec.mime_type,
                    file_rec.blob_content,
                    file_rec.filename,
                    x_request_id,
                    SYSDATE,
                    SYSDATE
                );
            END LOOP;
        END IF;

        -- 5. Link Tasks & Record in Request Log
        IF p_task_ids IS NOT NULL AND TRIM(p_task_ids) IS NOT NULL THEN
            BEGIN
                IF central.check_request_task(TO_NUMBER(p_task_ids)) = 1 THEN
                    UPDATE epromhq.trv_allowance
                       SET task_ids = p_task_ids
                     WHERE request_id = x_request_id;

                    INSERT INTO epromhq.request_log (
                        req_id,
                        req_start_rotation,
                        req_apply_rotation,
                        req_type
                    ) VALUES (
                        x_request_id,
                        get_emp_rotation(v_user, v_date_from),
                        get_emp_rotation(v_user, SYSDATE),
                        'TRAVEL_EXPENSE'
                    );
                END IF;
            EXCEPTION
                WHEN VALUE_ERROR OR INVALID_NUMBER THEN
                    -- If task_ids contains non-numeric list or tokens, preserve on record
                    UPDATE epromhq.trv_allowance
                       SET task_ids = p_task_ids
                     WHERE request_id = x_request_id;
            END;
        END IF;

        -- 6. Execute Business Allowance Calculations
        epromhq.calculate_allowance(
            p_request_id => x_request_id,
            p_app_user   => v_user
        );

    EXCEPTION
        WHEN OTHERS THEN
            v_err_msg := SQLERRM;
            -- If TRV_ALLOWANCE_CK_DATES_TYPE47 constraint is violated
            IF v_err_msg LIKE '%TRV_ALLOWANCE_CK_DATES_TYPE47%' THEN
                RAISE_APPLICATION_ERROR(
                    -20001,
                    'يجب إدخال تاريخ البداية وتاريخ النهاية للرحلات الخارجية.'
                );
            ELSE
                RAISE_APPLICATION_ERROR(
                    -20003,
                    'فشل حفظ طلب بدل الانتقال: ' || v_err_msg
                );
            END IF;
    END save_request;

    -- -------------------------------------------------------------------------
    -- Post-Workflow Hook: set_workflow_id
    -- -------------------------------------------------------------------------
    PROCEDURE set_workflow_id (
        p_request_id  IN NUMBER,
        p_workflow_id IN VARCHAR2
    ) IS
    BEGIN
        UPDATE epromhq.trv_allowance
           SET workflow_id = p_workflow_id
         WHERE request_id = p_request_id;
    END set_workflow_id;

END trv_allowance_pkg;
/
