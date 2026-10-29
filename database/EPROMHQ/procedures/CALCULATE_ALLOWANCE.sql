
  CREATE OR REPLACE EDITIONABLE PROCEDURE "EPROMHQ"."CALCULATE_ALLOWANCE" (
    p_request_id IN NUMBER,
    p_app_user   IN VARCHAR2
) IS
    l_site              VARCHAR2(180);
    l_trip_location     VARCHAR2(180);
    l_grade_str         VARCHAR2(4000);
    l_grade_num         NUMBER;
    l_date_from         DATE;
    l_date_to           DATE;
    l_return_same_day   NUMBER := 0;

    l_days              NUMBER := 0;
    l_hours             NUMBER := 0;
    l_distance          NUMBER := 299;
    l_rate              NUMBER := 0;
    l_final_rate        NUMBER := 0;
    l_meal              NUMBER := 0;
    l_total             NUMBER := 0;
    l_meal_flag         VARCHAR2(20);

    l_type_clean        VARCHAR2(20);
    l_factor            NUMBER := 1;
    l_row_days          NUMBER := 0;
    l_days_to_use       NUMBER := 0;
    l_remaining_days    NUMBER := 0;

    l_is_same_day       NUMBER := 0;
    l_is_meliha         NUMBER := 0;
    l_special_factor    NUMBER := 1;

BEGIN
    /* 1) بيانات الطلب */
    SELECT date_from,
           date_to,
           trip_location,
           NVL(distance_km, 299),
           NVL(return_same_day, 0)
      INTO l_date_from,
           l_date_to,
           l_trip_location,
           l_distance,
           l_return_same_day
      FROM epromhq.trv_allowance
     WHERE request_id = p_request_id;

    /* 2) بيانات الموظف */
    SELECT site_code,
           current_grade
      INTO l_site,
           l_grade_str
      FROM central.xxapex_hr_emp_data
     WHERE emp_number = p_app_user;

    /* 3) استخراج رقم الجريد */
    l_grade_num := TO_NUMBER(REGEXP_SUBSTR(TRIM(l_grade_str), '\d+$'));

    /* 4) حساب الساعات */
    l_hours := ROUND((l_date_to - l_date_from) * 24, 2);

    /* 5) حساب الأيام حسب قاعدة 12 ظهرًا */
    l_days := TRUNC(l_date_to) - TRUNC(l_date_from) + 1;

    /* يوم السفر لا يتحسب إذا كان 12:00 أو بعده */
    IF l_date_from >= TRUNC(l_date_from) + 12/24 THEN
        l_days := l_days - 1;
    END IF;

    /* يوم الرجوع لا يتحسب إذا كان 12:00 أو قبله */
    IF l_date_to <= TRUNC(l_date_to) + 12/24 THEN
        l_days := l_days - 1;
    END IF;

    IF l_days < 0 THEN
        l_days := 0;
    END IF;

    /* 6) تحديد قيمة اليوم الأساسية */
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

    /* 7) تحديد هل هي نفس اليوم */
    IF l_return_same_day = 1
       OR TRUNC(l_date_from) = TRUNC(l_date_to)
    THEN
        l_is_same_day := 1;
    ELSE
        l_is_same_day := 0;
    END IF;

    /* 8) تحديد هل المكان مليحة / عجيبة */
    IF TRIM(UPPER(NVL(l_trip_location, ''))) IN (
           UPPER('Meliha'),
           UPPER('مليحة'),
           UPPER('مليحه'),
           UPPER('AGIBA'),
           UPPER('عجيبة'),
           UPPER('EPROM_AGIBA'),
           UPPER('Melieha'),
           UPPER('MGP')

       )
    THEN
        l_is_meliha := 1;
    ELSE
        l_is_meliha := 0;
    END IF;

    /* 9) تطبيق نسبة 50% */
    IF l_is_same_day = 1 OR l_is_meliha = 1 THEN
        l_special_factor := 0.5;
    ELSE
        l_special_factor := 1;
    END IF;

    l_final_rate := l_rate * l_special_factor;

    /* 10) حساب الفنادق لكن بحد أقصى عدد أيام الرحلة */
    l_total := 0;
    l_remaining_days := l_days;

    FOR r IN (
        SELECT type_of_hotel,
               number_of_days
          FROM epromhq.trv_allowance_hotels
         WHERE request_id = p_request_id
         ORDER BY id
    ) LOOP
        EXIT WHEN l_remaining_days <= 0;

        /* تنظيف نوع الفندق */
        l_type_clean := UPPER(REPLACE(REPLACE(TRIM(r.type_of_hotel), '.', ''), ' ', ''));

        /* عدد أيام الصف */
        l_row_days := TO_NUMBER(TRIM(NVL(r.number_of_days, '0')));

        /* ناخد من الصف على قد الأيام المتبقية فقط */
        l_days_to_use := LEAST(l_row_days, l_remaining_days);

        /* تحديد المعامل */
        IF l_type_clean = 'BB' THEN
            l_factor := 0.75;
        ELSIF l_type_clean = 'HB' THEN
            l_factor := 0.50;
        ELSIF l_type_clean = 'FB' THEN
            l_factor := 0.50;
        ELSIF l_type_clean = 'SA' THEN
            l_factor := 1;
        ELSE
            l_factor := 1;
        END IF;

        /* إضافة القيمة */
        l_total := l_total + (l_days_to_use * l_final_rate * l_factor);

        /* تقليل الأيام المتبقية */
        l_remaining_days := l_remaining_days - l_days_to_use;
    END LOOP;

    /* لو مفيش فنادق أو الفنادق أقل من أيام الرحلة، الباقي يتحسب SA */
    IF l_remaining_days > 0 THEN
        l_total := l_total + (l_remaining_days * l_final_rate);
    END IF;

    /* 11) الوجبة فقط لو مكان الرحلة القاهرة والساعات 10 أو أكثر */
    IF REGEXP_LIKE(NVL(UPPER(l_trip_location), ' '), 'CAIRO|قاهرة|قاهره')
       AND l_hours >= 10
    THEN
        l_meal := 170;
    ELSE
        l_meal := 0;
    END IF;

    /* 12) إضافة الوجبة */
    l_total := l_total + l_meal;

    l_meal_flag := CASE WHEN l_meal > 0 THEN 'YES' ELSE 'NO' END;

    /* 13) تحديث الطلب */
    UPDATE epromhq.trv_allowance
       SET per_diem_rate   = l_final_rate,
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
            'يوجد خطأ في CURRENT_GRADE أو NUMBER_OF_DAYS. تأكد أن عدد الأيام رقم صحيح.'
        );
    WHEN OTHERS THEN
        ROLLBACK;
        RAISE;
END calculate_allowance;
/
