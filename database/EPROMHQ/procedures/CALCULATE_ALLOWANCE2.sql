
  CREATE OR REPLACE EDITIONABLE PROCEDURE "EPROMHQ"."CALCULATE_ALLOWANCE2" (
    p_request_id IN NUMBER,
    p_app_user   IN VARCHAR2
) IS
    ----------------------------------------------------------------------------
    -- Request Data
    ----------------------------------------------------------------------------
    l_site              VARCHAR2(180);
    l_grade_str         VARCHAR2(4000);
    l_grade_num         NUMBER;

    l_date_from         DATE;
    l_date_to           DATE;
    l_start_time        VARCHAR2(20);
    l_end_time          VARCHAR2(20);

    l_start_dt          DATE;
    l_end_dt            DATE;

    ----------------------------------------------------------------------------
    -- Calculation Variables
    ----------------------------------------------------------------------------
    l_distance          NUMBER := 299;
    l_rate              NUMBER := 0;

    l_total_hours       NUMBER := 0;
    l_meal_amount       NUMBER := 0;
    l_meal_flag         VARCHAR2(3) := 'NO';

    l_total_days        NUMBER := 0;
    l_eligible_days     NUMBER := 0;

    l_start_after_noon  NUMBER := 0;
    l_end_before_noon   NUMBER := 0;

    l_hotel_days        NUMBER := 0;
    l_non_hotel_days    NUMBER := 0;

    l_hotel_total       NUMBER := 0;
    l_total             NUMBER := 0;

    ----------------------------------------------------------------------------
    -- Function: Build DateTime from DATE + HH24:MI
    ----------------------------------------------------------------------------
    FUNCTION build_datetime (
        p_date IN DATE,
        p_time IN VARCHAR2
    ) RETURN DATE
    IS
        l_result DATE;
    BEGIN
        IF p_date IS NULL THEN
            RETURN NULL;
        END IF;

        IF p_time IS NULL THEN
            RETURN TRUNC(p_date);
        END IF;

        l_result :=
            TO_DATE(
                TO_CHAR(TRUNC(p_date), 'YYYY-MM-DD') || ' ' || TRIM(p_time),
                'YYYY-MM-DD HH24:MI'
            );

        RETURN l_result;

    EXCEPTION
        WHEN OTHERS THEN
            RAISE_APPLICATION_ERROR(
                -20011,
                'Invalid time format in START_TIME / END_TIME. Expected format like 19:30 or 08:15.'
            );
    END build_datetime;

BEGIN
    ----------------------------------------------------------------------------
    -- 1) Get request data
    ----------------------------------------------------------------------------
    SELECT date_from,
           date_to,
           start_time,
           end_time
      INTO l_date_from,
           l_date_to,
           l_start_time,
           l_end_time
      FROM epromhq.trv_allowance
     WHERE request_id = p_request_id;

    ----------------------------------------------------------------------------
    -- 2) Get employee data
    ----------------------------------------------------------------------------
    SELECT site_code,
           current_grade
      INTO l_site,
           l_grade_str
      FROM central.xxapex_hr_emp_data
     WHERE emp_number = p_app_user;

    ----------------------------------------------------------------------------
    -- 3) Extract grade number
    ----------------------------------------------------------------------------
    l_grade_num := TO_NUMBER(REGEXP_SUBSTR(TRIM(l_grade_str), '\d+$'));

    ----------------------------------------------------------------------------
    -- 4) Build actual datetime values
    ----------------------------------------------------------------------------
    l_start_dt := build_datetime(l_date_from, l_start_time);
    l_end_dt   := build_datetime(l_date_to,   l_end_time);

    IF l_start_dt IS NULL OR l_end_dt IS NULL THEN
        RAISE_APPLICATION_ERROR(-20012, 'Start date/time or end date/time is missing.');
    END IF;

    IF l_end_dt < l_start_dt THEN
        RAISE_APPLICATION_ERROR(-20013, 'End date/time cannot be earlier than start date/time.');
    END IF;

    ----------------------------------------------------------------------------
    -- 5) Total duration in hours
    ----------------------------------------------------------------------------
    l_total_hours := ROUND((l_end_dt - l_start_dt) * 24, 2);

    ----------------------------------------------------------------------------
    -- 6) Meal logic
    ----------------------------------------------------------------------------
    IF l_total_hours >= 10 THEN
        l_meal_flag   := 'YES';
        l_meal_amount := 170;
    ELSE
        l_meal_flag   := 'NO';
        l_meal_amount := 0;
    END IF;

    ----------------------------------------------------------------------------
    -- 7) Determine rate by site and grade
    ----------------------------------------------------------------------------
    IF l_site IN ('EPROM_HQ_CAIRO', 'EPROM_HQ_ALEX') THEN
        IF l_grade_num BETWEEN 1 AND 3 THEN
            l_rate := CASE WHEN l_distance < 300 THEN 480 ELSE 720 END;
        ELSIF l_grade_num BETWEEN 4 AND 9 THEN
            l_rate := CASE WHEN l_distance < 300 THEN 600 ELSE 820 END;
        ELSE
            l_rate := CASE WHEN l_distance < 300 THEN 720 ELSE 920 END;
        END IF;
    ELSE
        IF l_grade_num BETWEEN 1 AND 3 THEN
            l_rate := 600;
        ELSIF l_grade_num BETWEEN 4 AND 9 THEN
            l_rate := 820;
        ELSE
            l_rate := 920;
        END IF;
    END IF;

    ----------------------------------------------------------------------------
    -- 8) Total trip days
    ----------------------------------------------------------------------------
    l_total_days := TRUNC(l_date_to) - TRUNC(l_date_from) + 1;

    ----------------------------------------------------------------------------
    -- 9) Exclude first/last day based on noon rule
    ----------------------------------------------------------------------------
    IF TO_CHAR(l_start_dt, 'HH24:MI') > '12:00' THEN
        l_start_after_noon := 1;
    ELSE
        l_start_after_noon := 0;
    END IF;

    IF TO_CHAR(l_end_dt, 'HH24:MI') < '12:00' THEN
        l_end_before_noon := 1;
    ELSE
        l_end_before_noon := 0;
    END IF;

    l_eligible_days := l_total_days - l_start_after_noon - l_end_before_noon;

    IF l_eligible_days < 0 THEN
        l_eligible_days := 0;
    END IF;

    ----------------------------------------------------------------------------
    -- 10) Calculate hotels from TRV_ALLOWANCE_HOTELS
    ----------------------------------------------------------------------------
    SELECT NVL(SUM(TO_NUMBER(NVL(number_of_days, '0'))), 0),
           NVL(SUM(
                CASE UPPER(TRIM(type_of_hotel))
                    WHEN 'B.B' THEN TO_NUMBER(NVL(number_of_days, '0')) * l_rate * 0.75
                    WHEN 'H.B' THEN TO_NUMBER(NVL(number_of_days, '0')) * l_rate * 0.50
                    WHEN 'S.A' THEN TO_NUMBER(NVL(number_of_days, '0')) * l_rate * 1
                    ELSE 0
                END
           ), 0)
      INTO l_hotel_days,
           l_hotel_total
      FROM epromhq.trv_allowance_hotels
     WHERE request_id = p_request_id;

    ----------------------------------------------------------------------------
    -- 11) Validation: hotel days cannot exceed eligible days
    ----------------------------------------------------------------------------
    IF l_hotel_days > l_eligible_days THEN
        RAISE_APPLICATION_ERROR(
            -20014,
            'Total hotel days cannot be greater than eligible trip days.'
        );
    END IF;

    ----------------------------------------------------------------------------
    -- 12) Non-hotel days
    ----------------------------------------------------------------------------
    l_non_hotel_days := l_eligible_days - l_hotel_days;

    IF l_non_hotel_days < 0 THEN
        l_non_hotel_days := 0;
    END IF;

    ----------------------------------------------------------------------------
    -- 13) Final total
    ----------------------------------------------------------------------------
    l_total := (l_non_hotel_days * l_rate) + l_hotel_total + l_meal_amount;

    ----------------------------------------------------------------------------
    -- 14) Update request
    ----------------------------------------------------------------------------
    UPDATE epromhq.trv_allowance
       SET per_diem_rate   = l_rate,
           total_allowance = l_total,
           meal            = l_meal_flag,
           updated_at      = SYSDATE,
           updated_by      = p_app_user
     WHERE request_id = p_request_id;

    COMMIT;

EXCEPTION
    WHEN NO_DATA_FOUND THEN
        RAISE_APPLICATION_ERROR(-20001, 'Employee or Request not found.');
    WHEN VALUE_ERROR THEN
        RAISE_APPLICATION_ERROR(
            -20003,
            'Error converting numeric value. Please check CURRENT_GRADE or NUMBER_OF_DAYS.'
        );
    WHEN OTHERS THEN
        ROLLBACK;
        RAISE;
END calculate_allowance2;
/
