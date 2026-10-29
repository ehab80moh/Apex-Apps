
  CREATE OR REPLACE EDITIONABLE FUNCTION "EPROMHQ"."APP_ERROR_HANDLER" (
    p_error IN apex_error.t_error
) RETURN apex_error.t_error_result
IS
    l_result           apex_error.t_error_result;
    l_constraint_name  VARCHAR2(255);
BEGIN
    -- نبدأ بالسلوك الافتراضي بتاع APEX
    l_result := apex_error.init_error_result(p_error);

    ------------------------------------------------------------------
    -- 1) ORA-01400 على VAC_WINTER_COMPANIONS.PERSON_NAME (NOT NULL)
    ------------------------------------------------------------------
    IF p_error.ora_sqlcode = -1400
       AND INSTR(p_error.ora_sqlerrm,
                 'VAC_WINTER_COMPANIONS"."PERSON_NAME') > 0
    THEN
        l_result.message :=
            'برجاء إدخال اسم المرافق، حقل الاسم لا يمكن أن يكون فارغاً.';
        l_result.display_location := apex_error.c_inline_in_notification;
        RETURN l_result;
    END IF;

    ------------------------------------------------------------------
    -- 2) ORA-00001 على القيود الفريدة
    ------------------------------------------------------------------
    IF p_error.ora_sqlcode = -1 THEN
        -- استخراج اسم الـ constraint
        l_constraint_name :=
            apex_error.extract_constraint_name(p_error => p_error);

        IF l_constraint_name = 'VAC_WINTER_COMPANIONS_UK1' THEN
            l_result.message :=
                'هذا المرافق تم إضافته من قبل لنفس الطلب. برجاء عدم تكرار نفس الشخص.';
            l_result.display_location := apex_error.c_inline_in_notification;
            RETURN l_result;

            ELSIF
            l_constraint_name = 'TRIP_COMPANIONS_UK1' THEN
            l_result.message :=
                'هذا المرافق تم إضافته من قبل لنفس الطلب. برجاء عدم تكرار نفس الشخص.';
            l_result.display_location := apex_error.c_inline_in_notification;
            RETURN l_result;

        ELSIF l_constraint_name = 'VAC_WINTER_ROOMS_UK1' THEN
            l_result.message :=
                'لايمكن اختيار نفس الغرفه مرتين.';
            l_result.display_location := apex_error.c_inline_in_notification;
            RETURN l_result;

                    ELSIF l_constraint_name = 'TRIP_ROOMS_UK1' THEN
            l_result.message :=
                'لايمكن اختيار نفس الغرفه مرتين.';
            l_result.display_location := apex_error.c_inline_in_notification;
            RETURN l_result;

        END IF;
    END IF;

    ------------------------------------------------------------------
    -- 3) مثال: لو حابب تضيف ORA-01465 (رقم سداسي عشري غير صالح)
    --    تقدر تحط هنا هاندلينج خاص بيها
    ------------------------------------------------------------------
    /*
    IF p_error.ora_sqlcode = -1465 THEN
        l_result.message :=
            'حدث خطأ في حفظ أحد المرفقات، برجاء إعادة المحاولة أو إعادة رفع الملف.';
        l_result.display_location := apex_error.c_inline_in_notification;
        RETURN l_result;
    END IF;
    */

    ------------------------------------------------------------------
    -- 4) باقي الأخطاء: رجّع رسالة أوراكل الأصلية (Fallback)
    ------------------------------------------------------------------
    -- في الحالة دي إحنا بنقول:
    -- لو الخطأ مش واحد من اللي فوق → اعرض نص ORA-... زي ما هو
    l_result.message := p_error.ora_sqlerrm;
    l_result.display_location := apex_error.c_inline_in_notification;

    RETURN l_result;
END app_error_handler;
/
