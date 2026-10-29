
  CREATE OR REPLACE EDITIONABLE PACKAGE BODY "EPROMHQ"."SMS_PKG" AS
--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
--    FUNCTION send_single (
--        msg    VARCHAR2,
--        mobile VARCHAR2
--    ) RETURN NUMBER AS
--        l_clob CLOB;
--        l_obj  json_object_t := json_object_t();
--    BEGIN
--        l_obj.put('BankCode', 'EPROM');
--        l_obj.put('BankPWD', 'Epr0m@SMS7');
--        l_obj.put('SenderID', 'EPROM');
--        l_obj.put('MsgText', number_single_quotes(msg));
--        l_obj.put('MobileNo', mobile);
--        apex_web_service.g_request_headers(1).name := 'Content-type';
--        apex_web_service.g_request_headers(1).value := 'application/json';
--        l_clob := apex_web_service.make_rest_request(p_url => 'http://marketingportal.access2arabia.com:7766/JSON/API/A2A/SendSMS',
--        p_http_method => 'POST'
--        , p_body => l_obj.to_clob);
--        INSERT INTO central.sms_log (
--            msg,
--            mob,
--            log
--        ) VALUES (
--            msg,
--            mobile,
--            l_clob
--        );
--        COMMIT;
--        IF instr(l_clob, 'SUCCESS') > 1 THEN
--            RETURN 1;
--        END IF;
--        RETURN 0;
--    END send_single;
----------------------------------------------------------
    FUNCTION SEND_SINGLE (
        MSG    VARCHAR2,
        MOBILE VARCHAR2
    ) RETURN NUMBER AS
        L_RESP      CLOB;
        L_RC        NUMBER := 0;
        L_HTTP_CODE PLS_INTEGER := 0;
    BEGIN
  -- ترويسات الطلب
        APEX_WEB_SERVICE.G_REQUEST_HEADERS(1).NAME := 'Content-Type';
        APEX_WEB_SERVICE.G_REQUEST_HEADERS(1).VALUE := 'application/json; charset=UTF-8';

  -- بناء JSON آمن
        DECLARE
            L_OBJ JSON_OBJECT_T := JSON_OBJECT_T();
        BEGIN
            L_OBJ.PUT('BankCode', 'EPROM');
            L_OBJ.PUT('BankPWD', 'Epr0m@SMS7');
            L_OBJ.PUT('SenderID', 'EPROM');
            L_OBJ.PUT('MsgText', NUMBER_double_QUOTES(msg));      -- json_object_t هيهاندل الإسكابنج
            L_OBJ.PUT('MobileNo', MOBILE);
            L_RESP := APEX_WEB_SERVICE.MAKE_REST_REQUEST(P_URL => 'http://marketingportal.access2arabia.com:7766/JSON/API/A2A/SendSMS'
            , P_HTTP_METHOD => 'POST',
                                                        P_BODY => L_OBJ.TO_CLOB);

        END;

  -- كود الاستجابة HTTP
        L_HTTP_CODE := NVL(APEX_WEB_SERVICE.G_STATUS_CODE, 0);

  --判 النجاح: HTTP 2xx + وجود دلالة نجاح بالنص
        IF L_HTTP_CODE BETWEEN 200 AND 299 THEN
            IF INSTR(UPPER(L_RESP), 'SUCCESS') > 0 OR INSTR(UPPER(L_RESP), '"STATUS":"OK"') > 0 OR INSTR(UPPER(L_RESP), '"CODE":0') > 0
            OR INSTR(UPPER(L_RESP), '"ISSUCCESSFUL":TRUE') > 0 THEN
                L_RC := 1;
            ELSE
                L_RC := 0;
            END IF;
        ELSE
            L_RC := 0;
        END IF;

  -- سجل دايمًا (نجاح/فشل)
        LOG_SMS_ATTEMPT(P_MSG => NUMBER_double_QUOTES(msg), P_MOB => MOBILE,
                       P_LOG => L_RESP || TO_CLOB(' [HTTP:' || L_HTTP_CODE || ']'));

        RETURN L_RC;
    EXCEPTION
        WHEN OTHERS THEN
    -- لو حصل استثناء قبل التسجيل، نسجّل رسالة الخطأ
            L_RESP := TO_CLOB('ERROR ' || SQLCODE
                              || ': '
                              || SQLERRM);
            BEGIN
                LOG_SMS_ATTEMPT(P_MSG => NUMBER_double_QUOTES(msg), P_MOB => MOBILE,
                               P_LOG => L_RESP || TO_CLOB(' [HTTP:' || NVL(APEX_WEB_SERVICE.G_STATUS_CODE, 0) || ']'));

            EXCEPTION
                WHEN OTHERS THEN
                    NULL;
            END;

            RETURN 0;
    END;


    ----------------------------------------------------------
    FUNCTION GET_EMP_MOBILE (
        P_EMP       VARCHAR2,
        P_CONFIRMED NUMBER := 1
    ) RETURN VARCHAR2 AS
        V_MOB VARCHAR2(99);
    BEGIN
        SELECT
            MOBILE
        INTO V_MOB
        FROM
            EMP_CONTACT
        WHERE
                EMP_ID = P_EMP
            AND MOBILE_CONFIRMED = 1;

        RETURN V_MOB;
    EXCEPTION
        WHEN OTHERS THEN
            RETURN NULL;
    END;

--------------------------------------------------------------------------------
-- FUNCTION send_emp
--------------------------------------------------------------------------------
    FUNCTION SEND_EMP (
        P_EMP_ID     VARCHAR2,
        P_MSG        VARCHAR2,
        P_CHECK_PREF BOOLEAN := FALSE
    ) RETURN NUMBER AS
        V_MOB VARCHAR2(99);
        V_OK  BOOLEAN := TRUE;
    BEGIN
    --check preferences
        IF P_CHECK_PREF = FALSE THEN
            V_OK := TRUE;
        ELSIF
            P_CHECK_PREF
            AND PREF_PKG.GET_PREF(P_EMP_ID, 1) = 'yes'
        THEN
            V_OK := TRUE;
        ELSE
            V_OK := FALSE;
        END IF;
--------it's okay to send him
        IF V_OK THEN
            SELECT
                MOBILE
            INTO V_MOB
            FROM
                EMP_CONTACT
            WHERE
                    EMP_ID = P_EMP_ID
                AND MOBILE_CONFIRMED = 1;

              IF V_MOB IS NOT NULL THEN  --ASHARIF 2025-12-06
                RETURN SMS_PKG.ENQUEUE_SMS(P_SMS_TXT => P_MSG, P_SMS_TO => V_MOB);
                -- SEND_SINGLE(MSG => P_MSG, MOBILE => V_MOB);
            END IF;

        END IF;

        RETURN 0;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            RETURN 0;
        WHEN OTHERS THEN
            LOG_ERR_TABLE_AND_JSON(SQLERRM, 'sms_pkg.send_emp',
                                  FALSE);
            RETURN 0;
    END;
--------------------------------------------------------------------------------
    FUNCTION SEND_MULTI (
        MSG     VARCHAR2,
        MOBILES CLOB
    ) RETURN NUMBER AS
        L_CLOB CLOB;
        L_OBJ  JSON_OBJECT_T := JSON_OBJECT_T();
        L_ARR  JSON_ARRAY_T := JSON_ARRAY_T();
    BEGIN
        L_OBJ.PUT('BankCode', 'EPROM');
        L_OBJ.PUT('BankPWD', 'Epr0m@SMS7');
        L_OBJ.PUT('SenderID', 'EPROM');
        L_OBJ.PUT('MsgText', NUMBER_SINGLE_QUOTES(MSG));
        FOR M IN (
            SELECT
                COLUMN_VALUE NO
            FROM
                TABLE ( APEX_STRING.SPLIT(MOBILES, ':') )
        ) LOOP
            L_ARR.APPEND(JSON_OBJECT_T('{"MobileNo":"' || M.NO
                                       || '"}'));
        END LOOP;

        L_OBJ.PUT('MobilesNo', L_ARR);
        APEX_WEB_SERVICE.G_REQUEST_HEADERS(1).NAME := 'Content-type';
        APEX_WEB_SERVICE.G_REQUEST_HEADERS(1).VALUE := 'application/json';
        L_CLOB := APEX_WEB_SERVICE.MAKE_REST_REQUEST(P_URL => 'http://marketingportal.access2arabia.com:7766/JSON/API/A2A/SendCampSMS'
        , P_HTTP_METHOD => 'POST',
                                                    P_BODY => L_OBJ.TO_CLOB);

        INSERT INTO SMS_LOG (
            MSG,
            MOB,
            LOG
        ) VALUES (
            MSG,
            MOBILES,
            L_CLOB
        );

        COMMIT;
        IF INSTR(L_CLOB, 'SUCCESS') > 1 THEN
            RETURN 1;
        END IF;
        RETURN 0;
    END SEND_MULTI;
--------------------------------------------------------------------------------
    FUNCTION SEND_BULK (
        P_CAMP_ID NUMBER
    ) RETURN NUMBER AS

        CURSOR CR IS
        SELECT
            *
        FROM
            SMS_BULK_CAMPS
        WHERE
            CAMP_ID = P_CAMP_ID;

        L_OBJ    JSON_OBJECT_T := JSON_OBJECT_T();
        L_OBJ2   JSON_OBJECT_T := JSON_OBJECT_T();
        L_ARR    JSON_ARRAY_T := JSON_ARRAY_T();
        L_CLOB   CLOB;
        V_RETURN NUMBER;
    BEGIN
        FOR C IN CR LOOP
            V_RETURN := SMS_PKG.SEND_SINGLE(MSG => C.MSG, MOBILE => C.MOBILE);
        END LOOP;

        RETURN 1;
    -- send bulk does not work or too late
    /*
        l_obj.put('BankCode', 'EPROM');
        l_obj.put('BankPWD', 'Epr0m@SMS7');
        l_obj.put('SenderID', 'EPROM');
        l_obj.put('CampName', 'Camp: ' ||p_camp_id);
        FOR c IN cr LOOP
--        dbms_output.put_line(c.mobile);
        l_obj2:= json_object_t();
        l_obj2.put('MobileNo', c.mobile);
        l_obj2.put('MsgText', number_double_quotes2(C.msg));
--            l_arr.append(json_object_t('{"MobileNo":"'  || c.mobile|| '","MsgText":"'  || c.msg|| '"}'));
        l_arr.append(l_obj2);
        END LOOP;

        l_obj.put('messages', l_arr);
--        DBMS_OUTPUT.PUT_LINE(l_obj.to_clob);
        apex_web_service.g_request_headers(1).name := 'Content-type';
        apex_web_service.g_request_headers(1).value := 'application/json';
        l_clob := apex_web_service.make_rest_request(p_url => 'http://marketingportal.access2arabia.com:7766/JSON/API/A2A/SendBulkSMS'
        , p_http_method => 'POST', p_body => l_obj.to_clob);
-----------------------------------------
        INSERT INTO sms_log (
            msg,
            log
        ) VALUES (
            'Camp: ' ||p_camp_id,
            l_clob
        );
-----------------------------------------
        COMMIT;
        IF instr(l_clob, 'SUCCESS') > 1 THEN
            RETURN 1;
        END IF;
        RETURN 0;

        */

    END SEND_BULK;
-----------------------------------------------
    FUNCTION NUMBER_DOUBLE_QUOTES2 (
        P_TEXT VARCHAR2
    ) RETURN VARCHAR2 AS
    BEGIN
        RETURN REGEXP_REPLACE(P_TEXT, '(\d[a-zA-Z0-9/-]{1,}\d)',
                             '"\1"');
    END;


--------------------------------------------------------------------------------
    FUNCTION NUMBER_DOUBLE_QUOTES (
        P_TEXT VARCHAR2
    ) RETURN VARCHAR2 AS
    BEGIN
--        RETURN regexp_replace(p_text, '([0-9]+)', '"\1"'); --just surround all numbers
        RETURN REGEXP_REPLACE(P_TEXT, '(^|\s)([0-9]+)($|\s)',
                             '\1"\2"\3');--surround numbers between spaces
    END;
    ---------------------------
    FUNCTION NUMBER_SINGLE_QUOTES (
        P_TEXT VARCHAR2
    ) RETURN VARCHAR2 AS
    BEGIN
--        RETURN regexp_replace(p_text, '([0-9]+)', '"\1"'); --just surround all numbers
        RETURN REGEXP_REPLACE(P_TEXT, '(^|\s)([0-9]+)($|\s)',
                             '\1''\2''\3');
    END;
--------------------------------------------------------------------------------
    FUNCTION OTP (
        P_EMP IN VARCHAR2
    ) RETURN VARCHAR2 AS
        V_OTP VARCHAR2(6);
        I     NUMBER;
    BEGIN
        V_OTP := TRUNC(DBMS_RANDOM.VALUE(1111, 9999));
        UPDATE EMP_CRIDS
        SET
            OTP = V_OTP
        WHERE
            EMP_ID = P_EMP;

        I := SQL%ROWCOUNT;
        COMMIT;
        IF I > 0 THEN
            UPDATE EMP_CRIDS
            SET
                RESET_CODE_EXPIRE = SYSDATE + INTERVAL '1' HOUR
            WHERE
                EMP_ID = P_EMP;

            COMMIT;
            RETURN V_OTP;
        END IF;

        RETURN NULL;
    END OTP;
--------------------------------------------------------------------------------
    FUNCTION SEND_OTP (
        P_USER VARCHAR2,
        P_PASS VARCHAR2
    ) RETURN VARCHAR2 AS
        OTP      VARCHAR2(999);
        V_MOBILE VARCHAR2(999);
        V_SENT   NUMBER := 0;
    BEGIN


    -- Perform authentication
        IF NOT AUTH_EMP(P_USERNAME => P_USER, P_PASSWORD => P_PASS) THEN
        -- Consider logging or auditing failed authentication attempts

            RETURN 'خطأ في اسم المستخدم أو كلمة المرور';
        END IF;

        -- Retrieve mobile number
        SELECT
            MOBILE
        INTO V_MOBILE
        FROM
            CENTRAL.EMP_CONTACT
        WHERE
            EMP_ID = P_USER;

        -- Throttle SMS sent
        IF THROTTLE_OTP(P_USER) <> 1 THEN
            -- Log or handle excessive OTP requests
            RETURN 'تجاوزت الحد اليومي لإرسال أكواد التفعيل، لذا يُرجى إدخال آخر كود تم إرساله إلي' || ' '
                   || SUBSTR(V_MOBILE, -2)
                   || '******'
                   || SUBSTR(V_MOBILE, 1,
                            3);
        END IF;
            -- Generate OTP
        OTP := CENTRAL.SMS_PKG.OTP(P_EMP => P_USER);
        IF OTP IS NOT NULL THEN
        -- Attempt to send SMS
            V_SENT := CENTRAL.SMS_PKG.SEND_SINGLE(MSG => 'كود التفعيل هو "' || OTP || '"', MOBILE => V_MOBILE);
      -- Log the SMS details using the new procedure
            LOG_SMS_OTP_DETAILS(P_USER, OTP);
--          RETURN v_sent;
            IF V_SENT <> 1 THEN
            -- Consider logging or handling SMS sending issues
                RETURN 'مشكلة في إرسال الرسالة';
            ELSE
            -- Increase OTP count
                UPDATE EMP_CRIDS
                SET
                    OTP_COUNT = NVL(OTP_COUNT, 0) + 1
                WHERE
                    EMP_ID = P_USER;

            END IF;

            RETURN 'برجاء إدخال الرمز المرسل إلى هاتفك المحمول بالرقم ' || SUBSTR(V_MOBILE, -2)
                   || '******'
                   || SUBSTR(V_MOBILE, 1,
                            3);

        ELSE
        -- Redirect to a page if OTP is not generated
            APEX_UTIL.REDIRECT_URL(P_URL => APEX_PAGE.GET_URL(P_PAGE => 9990));
        END IF;

    EXCEPTION
        WHEN OTHERS THEN
        -- Log the error details
            LOG_ERR_TABLE_AND_JSON(SQLERRM, 'sms_pkg.send_otp',
                                  FALSE);

        -- Return a generic error message
            RETURN 'An unexpected error occurred. Please contact support.';
    END SEND_OTP;
    ----------------------------------------------------------------------------
    FUNCTION SEND_OTP2 (
        P_USER VARCHAR2,
        P_PASS VARCHAR2
    ) RETURN VARCHAR2 AS

        OTP      VARCHAR2(999);
        V_MOBILE VARCHAR2(999);
        V_SENT   NUMBER := 0;
        L_LANG   VARCHAR2(100);
    BEGIN
        L_LANG := GET_EMP_LANG(P_USER);
        IF NOT AUTH_EMP(P_USERNAME => P_USER, P_PASSWORD => P_PASS) THEN
            RETURN
                CASE
                    WHEN L_LANG = 'en-us' THEN
                        'Invalid username or password'
                    ELSE 'خطأ في اسم المستخدم أو كلمة المرور'
                END;
        END IF;

        SELECT
            MOBILE
        INTO V_MOBILE
        FROM
            CENTRAL.EMP_CONTACT
        WHERE
            EMP_ID = P_USER;

        IF THROTTLE_OTP(P_USER) <> 1 THEN
            RETURN
                CASE
                    WHEN L_LANG = 'en-us' THEN
                        'You have exceeded the daily limit for OTP requests. Please use the last code sent to ' || SUBSTR(V_MOBILE, -2
                        )
                        || '******'
                        || SUBSTR(V_MOBILE, 1,
                                 3)
                    ELSE 'تجاوزت الحد اليومي لإرسال أكواد التفعيل، لذا يُرجى إدخال آخر كود تم إرساله إلي' || SUBSTR(V_MOBILE, -2)
                         || '******'
                         || SUBSTR(V_MOBILE, 1,
                                  3)
                END;
        END IF;

        OTP := CENTRAL.SMS_PKG.OTP(P_EMP => P_USER);
        IF OTP IS NOT NULL THEN
            V_SENT := CENTRAL.SMS_PKG.SEND_SINGLE(MSG =>
                                                       CASE
                                                           WHEN L_LANG = 'en-us' THEN
                                                               'Your activation code is "' || OTP || '"'
                                                           ELSE
                                                               'كود التفعيل هو "' || OTP || '"'
                                                       END, MOBILE => V_MOBILE);

            LOG_SMS_OTP_DETAILS(P_USER, OTP);
            IF V_SENT <> 1 THEN
                RETURN
                    CASE
                        WHEN L_LANG = 'en-us' THEN
                            'There was a problem sending the message.'
                        ELSE 'مشكلة في إرسال الرسالة'
                    END;
            ELSE
                UPDATE EMP_CRIDS
                SET
                    OTP_COUNT = NVL(OTP_COUNT, 0) + 1
                WHERE
                    EMP_ID = P_USER;

                RETURN
                    CASE
                        WHEN L_LANG = 'en-us' THEN
                            'Please enter the code sent to your mobile ending with ' || SUBSTR(V_MOBILE, -2)
                            || '******'
                            || SUBSTR(V_MOBILE, 1,
                                     3)
                        ELSE 'برجاء إدخال الرمز المرسل إلى هاتفك المحمول بالرقم ' || SUBSTR(V_MOBILE, -2)
                             || '******'
                             || SUBSTR(V_MOBILE, 1,
                                      3)
                    END;

            END IF;

        ELSE
            APEX_UTIL.REDIRECT_URL(P_URL => APEX_PAGE.GET_URL(P_PAGE => 9990));
        END IF;

    EXCEPTION
        WHEN OTHERS THEN
            LOG_ERR_TABLE_AND_JSON(SQLERRM, 'sms_pkg.send_otp2',
                                  FALSE);
            RETURN
                CASE
                    WHEN L_LANG = 'en-us' THEN
                        'An unexpected error occurred. Please contact support.'
--               ELSE 'حدث خطأ غير متوقع. يرجى التواصل مع الدعم الفني..'
                    ELSE 'برجاء إدخال الرمز المرسل إلى هاتفك المحمول بالرقم ' || SUBSTR(V_MOBILE, -2)
                         || '******'
                         || SUBSTR(V_MOBILE, 1,
                                  3)
                END;

    END SEND_OTP2;

--------------------------------------------------------------------------------
    FUNCTION CHECK_OTP (
        P_USER VARCHAR2,
        P_OTP  VARCHAR2
    ) RETURN NUMBER AS
        L_RET NUMBER := 0;
    BEGIN
   -- Select count of rows where conditions are met
        SELECT
            COUNT(*)
        INTO L_RET
        FROM
            EMP_CRIDS
        WHERE
                EMP_ID = P_USER
            AND OTP = P_OTP
            AND RESET_CODE_EXPIRE > SYSDATE - INTERVAL '1' HOUR;

        IF L_RET > 0 THEN
        --TODO email confirm if otp is sent via email
            UPDATE EMP_CONTACT
            SET
                MOBILE_CONFIRMED = 1
            WHERE
                EMP_ID = P_USER;

        END IF;
-- log otp attempt for throttling field attempts

        INSERT INTO CENTRAL.LOGIN_AUTH_LOG (
            USERNAME,
            LOGIN_DATE,
            STATUS,
            APP,
            OTP_STATUS,
            OTP_ENTERED
        ) VALUES (
            P_USER,
            SYSDATE,
            1,
            SYS_CONTEXT('APEX$SESSION', 'APP_ID'),
            L_RET,
            P_OTP
        );

        COMMIT;
   -- Return the count as the result
        RETURN L_RET;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
      -- If no data is found, return 0 (indicating invalid OTP)
            RETURN 0;
        WHEN OTHERS THEN
      -- Log error and return 0 in case of other exceptions
            LOG_ERR_TABLE_AND_JSON(SQLERRM, 'sms_pkg.check_otp',
                                  FALSE);
            RETURN 0;
    END;

--------------------------------------------------------------------------------
    FUNCTION SEND_RESET_CODE (
        P_USER VARCHAR2
    ) RETURN NUMBER AS
        V_MOBILE VARCHAR2(99);
        V_SENT   NUMBER := 0;
        V_CODE   VARCHAR2(99);
    BEGIN
  -- Validate input type
        IF P_USER IS NULL OR LENGTH(P_USER) < 1 THEN
    -- Handle invalid input type (non-digit characters)
            RETURN 0;
        END IF;

  -- Get user's mobile number
        SELECT
            MOBILE
        INTO V_MOBILE
        FROM
            CENTRAL.EMP_CONTACT
        WHERE
            EMP_ID = P_USER;

  -- Throttle SMS sent
        IF THROTTLE_RESET_CODE_for_pass(P_USER) <> 1 THEN
    -- Log or handle excessive OTP requests
            APEX_ERROR.ADD_ERROR(P_MESSAGE => 'تم تجاوز الحد الاقصى لرسائل التفعيل برجاء استخدام اخر كود', P_DISPLAY_LOCATION => APEX_ERROR.C_INLINE_IN_NOTIFICATION
            );
            RETURN 0; -- You may want to return a more specific error code
        END IF;

  -- Generate a new reset code
        V_CODE := CENTRAL.SET_EMP_REST_CODE(P_EMP_ID => P_USER);


  -- Send SMS with reset code
        V_SENT := CENTRAL.SMS_PKG.SEND_SINGLE(MOBILE => V_MOBILE, MSG => 'كود التفعيل الخاص بكم' || ' ' || V_CODE || ' ' || 'برجاء متابعة الخطوات او زيارة https://bit.ly/4aM9Pu5 في خلال ساعة'
        );

  -- Handle SMS sending errors
        IF V_SENT <> 1 THEN
            APEX_ERROR.ADD_ERROR(P_MESSAGE => 'يوجد خطأ ما في ارسال الرسالة', P_DISPLAY_LOCATION => APEX_ERROR.C_INLINE_IN_NOTIFICATION
            );
        END IF;

  -- Log the SMS details using the new procedure
        LOG_SMS_OTP_DETAILS(P_USER, V_CODE);
        RETURN V_SENT;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
    -- Handle case where no mobile number is found
            APEX_ERROR.ADD_ERROR(P_MESSAGE => 'يوجد خطأ لا توجد بيانات', P_DISPLAY_LOCATION => APEX_ERROR.C_INLINE_IN_NOTIFICATION);
            RETURN 0;
        WHEN OTHERS THEN
            APEX_ERROR.ADD_ERROR(P_MESSAGE => 'يوجد خطأ غير متوقع في ارسال الرسالة', P_DISPLAY_LOCATION => APEX_ERROR.C_INLINE_IN_NOTIFICATION
            );
    -- Log the error
            LOG_ERR_TABLE_AND_JSON(SQLERRM, 'sms_pkg.send_reset_code',
                                  FALSE);
            RETURN 0;
    END SEND_RESET_CODE;
--------------------------------------------------------------------------------

    FUNCTION SEND_RESET_CODE2 (
        P_USER VARCHAR2
    ) RETURN NUMBER AS

        V_MOBILE VARCHAR2(99);
        V_SENT   NUMBER := 0;
        V_CODE   VARCHAR2(99);
        L_LANG   VARCHAR2(10);
    BEGIN
  -- استرجاع اللغة من عنصر APEX
        L_LANG := GET_EMP_LANG(P_USER);

  -- التحقق من الإدخال
        IF P_USER IS NULL OR LENGTH(P_USER) < 1 THEN
            RETURN 0;
        END IF;

  -- الحصول على رقم الهاتف
        SELECT
            MOBILE
        INTO V_MOBILE
        FROM
            CENTRAL.EMP_CONTACT
        WHERE
            EMP_ID = P_USER;

  -- تحقق من عدد الرسائل المسموح بها
        IF THROTTLE_RESET_CODE(P_USER) <> 1 THEN
            APEX_ERROR.ADD_ERROR(P_MESSAGE =>
                                            CASE
                                                WHEN L_LANG = 'en-us' THEN
                                                    'You have exceeded the maximum limit for reset messages. Please use the last code sent.'
                                                ELSE
                                                    'تم تجاوز الحد الأقصى لرسائل التفعيل، برجاء استخدام آخر كود تم إرساله.'
                                            END, P_DISPLAY_LOCATION => APEX_ERROR.C_INLINE_IN_NOTIFICATION);

            RETURN 0;
        END IF;

  -- توليد كود جديد
        V_CODE := CENTRAL.SET_EMP_REST_CODE(P_EMP_ID => P_USER);

  -- إرسال الرسالة النصية
        V_SENT := CENTRAL.SMS_PKG.SEND_SINGLE(MOBILE => V_MOBILE, MSG =>
                                                                       CASE
                                                                           WHEN L_LANG = 'en-us' THEN
                                                                               'Your reset code is "' || V_CODE || '". Please continue the steps or visit https://bit.ly/4aM9Pu5 within 1 hour.'
                                                                           ELSE
                                                                               'كود التفعيل الخاص بكم "' || V_CODE || '" برجاء متابعة الخطوات أو زيارة https://bit.ly/4aM9Pu5 في خلال ساعة.'
                                                                       END
                  );

  -- التعامل مع فشل الإرسال
        IF V_SENT <> 1 THEN
            APEX_ERROR.ADD_ERROR(P_MESSAGE =>
                                            CASE
                                                WHEN L_LANG = 'en-us' THEN
                                                    'There was an error sending the message.'
                                                ELSE
                                                    'يوجد خطأ ما في إرسال الرسالة'
                                            END, P_DISPLAY_LOCATION => APEX_ERROR.C_INLINE_IN_NOTIFICATION);
        END IF;

  -- تسجيل تفاصيل الرسالة
        LOG_SMS_OTP_DETAILS(P_USER, V_CODE);
        RETURN V_SENT;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            APEX_ERROR.ADD_ERROR(P_MESSAGE =>
                                            CASE
                                                WHEN L_LANG = 'en-us' THEN
                                                    'No data found for this user.'
                                                ELSE
                                                    'يوجد خطأ، لا توجد بيانات لهذا المستخدم'
                                            END, P_DISPLAY_LOCATION => APEX_ERROR.C_INLINE_IN_NOTIFICATION);

            RETURN 0;
        WHEN OTHERS THEN
            APEX_ERROR.ADD_ERROR(P_MESSAGE =>
                                            CASE
                                                WHEN L_LANG = 'en-us' THEN
                                                    'Unexpected error while sending the message.'
                                                ELSE
                                                    'يوجد خطأ غير متوقع في إرسال الرسالة'
                                            END, P_DISPLAY_LOCATION => APEX_ERROR.C_INLINE_IN_NOTIFICATION);

            LOG_ERR_TABLE_AND_JSON(SQLERRM, 'sms_pkg.send_reset_code',
                                  FALSE);
            RETURN 0;
    END SEND_RESET_CODE2;


--------------------------------------------------------------------------------
--    FUNCTION THROTTLE_OTP (
--        P_USER VARCHAR2
--    ) RETURN NUMBER AS
--        L_COUNT NUMBER;
--    BEGIN
--  -- Retrieve the count of OTPs sent today for the specified user
--        SELECT
--            OTP_COUNT
--        INTO L_COUNT
--        FROM
--            EMP_CRIDS
--        WHERE
--                EMP_ID = P_USER
--            AND TRUNC(RESET_CODE_EXPIRE) = TRUNC(SYSDATE);
--
--  -- Check if the count exceeds the threshold
--        IF
--            L_COUNT >= 3
--            AND P_USER not in ('3199','1825','1837')
--        THEN
--            RETURN 0; -- Exceeded, return 0
--        ELSE
--            RETURN 1; -- Within the threshold, return 1
--        END IF;
--
--    EXCEPTION
--        WHEN NO_DATA_FOUND THEN
--            RETURN 1; -- No data found, within the threshold
--    END;

FUNCTION THROTTLE_OTP (
    P_USER VARCHAR2
) RETURN NUMBER
AS
    L_COUNT NUMBER := 0;
    L_LIMIT NUMBER;
BEGIN
    -- تحديد الحد حسب المستخدم
    IF P_USER IN ('1825','3199','1837') THEN
        L_LIMIT := 10;
    ELSE
        L_LIMIT := 3;
    END IF;

    -- جلب عدد الأكواد المرسلة اليوم
    SELECT OTP_COUNT
    INTO   L_COUNT
    FROM   EMP_CRIDS
    WHERE  EMP_ID = P_USER
    AND    TRUNC(RESET_CODE_EXPIRE) = TRUNC(SYSDATE);

    -- التحقق من تجاوز الحد
    IF L_COUNT >= L_LIMIT THEN
        RETURN 0; -- تجاوز الحد
    ELSE
        RETURN 1; -- مسموح
    END IF;

EXCEPTION
    WHEN NO_DATA_FOUND THEN
        RETURN 1; -- مفيش تسجيل اليوم → مسموح
END;

--------------------------------------------------------------------------------
    FUNCTION SEND_AND_RESET_NUMBER_PHONE (
        P_USER VARCHAR2
    ) RETURN VARCHAR2 AS
        OTP      VARCHAR2(99);
        V_MOBILE VARCHAR2(99);
        V_SENT   NUMBER := 0;
    BEGIN
    -- Retrieve mobile number
        SELECT
            MOBILE
        INTO V_MOBILE
        FROM
            CENTRAL.EMP_CONTACT
        WHERE
            EMP_ID = P_USER;

    -- Generate OTP
        OTP := CENTRAL.SMS_PKG.OTP(P_EMP => P_USER);
        IF OTP IS NOT NULL THEN
      -- Attempt to send SMS
            V_SENT := CENTRAL.SMS_PKG.SEND_SINGLE(MSG => 'كود لتغيير رقم الهاتف هو "' || OTP || '"', MOBILE => V_MOBILE);

      -- Log the SMS details using the new procedure
            LOG_SMS_OTP_DETAILS(P_USER, OTP);
        ELSE
      -- Increase OTP count
            UPDATE EMP_CRIDS
            SET
                OTP_COUNT = NVL(OTP_COUNT, 0) + 1
            WHERE
                EMP_ID = P_USER;

        END IF;

        RETURN NULL;
    EXCEPTION
        WHEN OTHERS THEN
      -- Log the error details
            LOG_ERR_TABLE_AND_JSON(SQLERRM, 'sms_pkg.send_and_reset_number_phone',
                                  FALSE);

      -- Return a generic error message
            RETURN 'An unexpected error occurred. Please contact support.';
    END SEND_AND_RESET_NUMBER_PHONE;
  ------------------------------------------------------------------------------

    FUNCTION SEND_AND_RESET_NUMBER_PHONE2 (
        P_USER VARCHAR2
    ) RETURN VARCHAR2 AS

        OTP      VARCHAR2(99);
        V_MOBILE VARCHAR2(99);
        V_SENT   NUMBER := 0;
        L_LANG   VARCHAR2(10);
    BEGIN
    -- استرجاع اللغة المفضلة للمستخدم
        L_LANG := GET_EMP_LANG(P_USER);

    -- جلب رقم الموبايل
        SELECT
            MOBILE
        INTO V_MOBILE
        FROM
            CENTRAL.EMP_CONTACT
        WHERE
            EMP_ID = P_USER;

    -- توليد كود التفعيل
        OTP := CENTRAL.SMS_PKG.OTP(P_EMP => P_USER);
        IF OTP IS NOT NULL THEN
        -- إرسال الرسالة
            V_SENT := CENTRAL.SMS_PKG.SEND_SINGLE(MSG =>
                                                       CASE
                                                           WHEN L_LANG = 'en-us' THEN
                                                               'The code to reset your phone number is "' || OTP || '"'
                                                           ELSE
                                                               'كود لتغيير رقم الهاتف هو "' || OTP || '"'
                                                       END, MOBILE => V_MOBILE);

        -- تسجيل الكود المرسل
            LOG_SMS_OTP_DETAILS(P_USER, OTP);

        -- زيادة العداد
            UPDATE EMP_CRIDS
            SET
                OTP_COUNT = NVL(OTP_COUNT, 0) + 1
            WHERE
                EMP_ID = P_USER;

        -- رسالة نجاح
            RETURN
                CASE
                    WHEN L_LANG = 'en-us' THEN
                        'Reset code sent successfully.'
                    ELSE 'تم إرسال كود تغيير الرقم بنجاح.'
                END;
        ELSE
        -- فشل في توليد الكود
            RETURN
                CASE
                    WHEN L_LANG = 'en-us' THEN
                        'Failed to generate the reset code.'
                    ELSE 'فشل في توليد كود التفعيل.'
                END;
        END IF;

    EXCEPTION
        WHEN OTHERS THEN
        -- تسجيل الخطأ
            LOG_ERR_TABLE_AND_JSON(SQLERRM, 'sms_pkg.send_and_reset_number_phone',
                                  FALSE);

        -- رسالة خطأ عامة
            RETURN
                CASE
                    WHEN L_LANG = 'en-us' THEN
                        'An unexpected error occurred. Please contact support.'
                    ELSE 'حدث خطأ غير متوقع. يرجى التواصل مع الدعم الفني.'
                END;
    END SEND_AND_RESET_NUMBER_PHONE2;

--------------------------------------------------------------------------------
    FUNCTION SEND_AND_CHANGE_PHONE (
        P_USER VARCHAR2
    ) RETURN VARCHAR2 AS
        OTP      VARCHAR2(99);
        V_MOBILE VARCHAR2(99);
        V_SENT   NUMBER := 0;
    BEGIN
    -- Retrieve mobile number
        SELECT
            MOBILE2
        INTO V_MOBILE
        FROM
            CENTRAL.EMP_CONTACT
        WHERE
            EMP_ID = P_USER;

    -- Generate OTP
        OTP := CENTRAL.SMS_PKG.OTP(P_EMP => P_USER);
        IF OTP IS NOT NULL THEN
      -- Attempt to send SMS
            V_SENT := CENTRAL.SMS_PKG.SEND_SINGLE(MSG => 'كود تغيير رقم الهاتف الجديد هو "' || OTP || '"', MOBILE => V_MOBILE);

      -- Log the SMS details using the new procedure
            LOG_SMS_OTP_DETAILS(P_USER, OTP);
        ELSE
      -- Increase OTP count
            UPDATE EMP_CRIDS
            SET
                OTP_COUNT = NVL(OTP_COUNT, 0) + 1
            WHERE
                EMP_ID = P_USER;

        END IF;

        RETURN NULL;
    EXCEPTION
        WHEN OTHERS THEN
      -- Log the error details
            LOG_ERR_TABLE_AND_JSON(SQLERRM, 'sms_pkg.send_and_change_phone',
                                  FALSE);

      -- Return a generic error message
            RETURN 'An unexpected error occurred. Please contact support.';
    END SEND_AND_CHANGE_PHONE;
--------------------------------------------------------------------------------

    FUNCTION SEND_AND_CHANGE_PHONE2 (
        P_USER VARCHAR2
    ) RETURN VARCHAR2 AS

        OTP      VARCHAR2(99);
        V_MOBILE VARCHAR2(99);
        V_SENT   NUMBER := 0;
        L_LANG   VARCHAR2(10);
    BEGIN
    -- استرجاع اللغة المفضلة للمستخدم
        L_LANG := GET_EMP_LANG(P_USER);

    -- جلب رقم الموبايل الجديد
        SELECT
            MOBILE2
        INTO V_MOBILE
        FROM
            CENTRAL.EMP_CONTACT
        WHERE
            EMP_ID = P_USER;

    -- توليد كود التفعيل
        OTP := CENTRAL.SMS_PKG.OTP(P_EMP => P_USER);
        IF OTP IS NOT NULL THEN
        -- إرسال الرسالة
            V_SENT := CENTRAL.SMS_PKG.SEND_SINGLE(MSG =>
                                                       CASE
                                                           WHEN L_LANG = 'en-us' THEN
                                                               'The code to change your new phone number is "' || OTP || '"'
                                                           ELSE
                                                               'كود تغيير رقم الهاتف الجديد هو "' || OTP || '"'
                                                       END, MOBILE => V_MOBILE);

        -- تسجيل تفاصيل الإرسال
            LOG_SMS_OTP_DETAILS(P_USER, OTP);

        -- زيادة العداد
            UPDATE EMP_CRIDS
            SET
                OTP_COUNT = NVL(OTP_COUNT, 0) + 1
            WHERE
                EMP_ID = P_USER;

        -- رسالة نجاح
            RETURN
                CASE
                    WHEN L_LANG = 'en-us' THEN
                        'Code sent to the new phone number successfully.'
                    ELSE 'تم إرسال الكود إلى الرقم الجديد بنجاح.'
                END;
        ELSE
        -- فشل في توليد الكود
            RETURN
                CASE
                    WHEN L_LANG = 'en-us' THEN
                        'Failed to generate the verification code.'
                    ELSE 'فشل في توليد كود التفعيل.'
                END;
        END IF;

    EXCEPTION
        WHEN OTHERS THEN
        -- تسجيل الخطأ
            LOG_ERR_TABLE_AND_JSON(SQLERRM, 'sms_pkg.send_and_change_phone',
                                  FALSE);

        -- رسالة خطأ عامة
            RETURN
                CASE
                    WHEN L_LANG = 'en-us' THEN
                        'An unexpected error occurred. Please contact support.'
                    ELSE 'حدث خطأ غير متوقع. يرجى التواصل مع الدعم الفني.'
                END;
    END SEND_AND_CHANGE_PHONE2;

---------------------------------------------------------------------------------
-- update the sent otp_sms

    FUNCTION SEND_OTP3 (
        P_USER VARCHAR2,
        P_PASS VARCHAR2
    ) RETURN VARCHAR2
-- AUTHID CURRENT_USER -- فعّل ده لو عايز تمشي بصلاحيات المستدعي
     AS

        L_OTP    VARCHAR2(100);
        L_MOBILE VARCHAR2(50);
        L_SENT   NUMBER := 0;
        L_LANG   VARCHAR2(10);
    BEGIN
        L_LANG := NVL(GET_EMP_LANG(P_USER), 'ar-ae');

  -- 1) تحقق من المستخدم/كلمة المرور
        IF NOT AUTH_EMP(P_USERNAME => P_USER, P_PASSWORD => P_PASS) THEN
            RETURN
                CASE
                    WHEN L_LANG = 'en-us' THEN
                        'Invalid username or password'
                    ELSE 'خطأ في اسم المستخدم أو كلمة المرور'
                END;
        END IF;

  -- 2) اجلب الموبايل وتعامل مع غياب/تكرار البيانات
        BEGIN
            SELECT
                MOBILE
            INTO L_MOBILE
            FROM
                CENTRAL.EMP_CONTACT
            WHERE
                EMP_ID = P_USER;

        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                RETURN
                    CASE
                        WHEN L_LANG = 'en-us' THEN
                            'No mobile number found. Please update your contact info.'
                        ELSE 'لا يوجد رقم هاتف مسجل. برجاء تحديث بياناتك واضافة رقم الموبايل بادارة بالموارد البشرية.'
                    END;
            WHEN TOO_MANY_ROWS THEN
                RETURN
                    CASE
                        WHEN L_LANG = 'en-us' THEN
                            'Multiple mobiles found. Please contact HR.'
                        ELSE 'تم العثور على أكثر من رقم. برجاء التواصل مع الموارد البشرية.'
                    END;
        END;

  -- 3) تحقّق من صيغة الموبايل
        IF L_MOBILE IS NULL OR NOT REGEXP_LIKE(L_MOBILE, '^[0-9]{10,15}$') THEN
            RETURN
                CASE
                    WHEN L_LANG = 'en-us' THEN
                        'Invalid mobile format. Please contact HR.'
                    ELSE 'صيغة رقم الجوال غير صحيحة. برجاء التواصل مع الموارد البشرية.'
                END;
        END IF;

  -- 4) Throttle
        IF THROTTLE_OTP(P_USER) <> 1 THEN
            RETURN
                CASE
                    WHEN L_LANG = 'en-us' THEN
                        'You have exceeded the daily limit for OTP requests. Please use the last code sent to ' || SUBSTR(L_MOBILE, -2
                        )
                        || '******'
                        || SUBSTR(L_MOBILE, 1,
                                 3)
                    ELSE 'تجاوزت الحد اليومي لإرسال أكواد التفعيل، يُرجى إدخال آخر كود مُرسل إلى ' || SUBSTR(L_MOBILE, -2)
                         || '******'
                         || SUBSTR(L_MOBILE, 1,
                                  3)
                END;
        END IF;

  -- 5) توليد الكود وإرساله
        L_OTP := CENTRAL.SMS_PKG.OTP(P_EMP => P_USER);
        IF L_OTP IS NULL THEN
            RETURN
                CASE
                    WHEN L_LANG = 'en-us' THEN
                        'Could not generate OTP. Please try again later.'
                    ELSE 'تعذر إنشاء كود التفعيل. برجاء المحاولة لاحقًا.'
                END;
        END IF;

        L_SENT := CENTRAL.SMS_PKG.SEND_SINGLE(MSG =>
                                                   CASE
                                                       WHEN L_LANG = 'en-us' THEN
                                                           'Your activation code is "' || L_OTP || '"'
                                                       ELSE
                                                           'كود التفعيل هو "' || L_OTP || '"'
                                                   END, MOBILE => L_MOBILE);

        LOG_SMS_OTP_DETAILS(P_USER, L_OTP);
        IF L_SENT <> 1 THEN
            RETURN
                CASE
                    WHEN L_LANG = 'en-us' THEN
--                    'Please enter the code sent to your mobile ending with '
--                || SUBSTR(l_mobile, -2) || '******' || SUBSTR(l_mobile, 1, 3)
--
                        'There was a problem sending the message.'
--  ELSE
--              'برجاء إدخال الرمز المرسل إلى رقمك المنتهي بـ '
--                || SUBSTR(l_mobile, -2) || '******' || SUBSTR(l_mobile, 1, 3)
--
                    ELSE 'حدثت مشكلة أثناء إرسال الرسالة.'
                END;
        END IF;

  -- 6) زيادة العداد (لو الصف غير موجود أنشئه)
        UPDATE EMP_CRIDS
        SET
            OTP_COUNT = NVL(OTP_COUNT, 0) + 1
        WHERE
            EMP_ID = P_USER;

        IF SQL%ROWCOUNT = 0 THEN
            INSERT INTO EMP_CRIDS (
                EMP_ID,
                OTP_COUNT
            ) VALUES (
                P_USER,
                1
            );

        END IF;

        RETURN
            CASE
                WHEN L_LANG = 'en-us' THEN
                    'Please enter the code sent to your mobile ending with ' || SUBSTR(L_MOBILE, -2)
                    || '******'
                    || SUBSTR(L_MOBILE, 1,
                             3)
                ELSE 'برجاء إدخال الرمز المرسل إلى رقمك المنتهي بـ ' || SUBSTR(L_MOBILE, -2)
                     || '******'
                     || SUBSTR(L_MOBILE, 1,
                              3)
            END;

    EXCEPTION
        WHEN OTHERS THEN
    -- سجّل كل التفاصيل (الكود + الستاك) في اللوج
            BEGIN
                LOG_ERR_TABLE_AND_JSON(DBMS_UTILITY.FORMAT_ERROR_STACK || ' | '
                                       || DBMS_UTILITY.FORMAT_ERROR_BACKTRACE, 'sms_pkg.send_otp2',
                                      FALSE);
            EXCEPTION
                WHEN OTHERS THEN
                    NULL;
            END;

            RETURN
                CASE
                    WHEN L_LANG = 'en-us' THEN
                        'An unexpected error occurred. Please contact support.'
                    ELSE 'حدث خطأ غير متوقع. يرجى التواصل مع الدعم الفني.'
                END;
    END SEND_OTP3;

--------------------------------------------------------------------------------
-- FUNCTION send_court_session_notification
--------------------------------------------------------------------------------
    FUNCTION SEND_COURT_SESSION_NOTIFICATION (
        P_EMP_ID      VARCHAR2,
        P_END_DATE    DATE,
        P_COURT_NAME  VARCHAR2,
        P_CASE_NUMBER VARCHAR2,
        P_CHECK_PREF  BOOLEAN := TRUE
    ) RETURN NUMBER AS
        V_MOB     VARCHAR2(99);
        V_SENT    NUMBER := 0;
        V_MESSAGE VARCHAR2(500);
    BEGIN
    -- Build the message
        V_MESSAGE := 'تاريخ جلسة المحكمة القادمة ' || TO_CHAR(P_END_DATE, 'DD-MM-YYYY')
                     || ' بمحكمة '
                     || P_COURT_NAME
                     || ' وهذا بقضية رقم '
                     || P_CASE_NUMBER;

    -- Retrieve employee's mobile number
        SELECT
            MOBILE
        INTO V_MOB
        FROM
            EMP_CONTACT
        WHERE
                EMP_ID = P_EMP_ID
            AND MOBILE_CONFIRMED = 1;

--    -- Check preference
--    IF p_check_pref AND pref_pkg.get_pref(p_emp_id, 1) != 'yes' THEN
--        RETURN 0; -- Preference to not receive notifications
--    END IF;

    -- Send SMS
        IF V_MOB IS NOT NULL THEN
            V_SENT := SEND_SINGLE(MSG => V_MESSAGE, MOBILE => V_MOB);
        END IF;

        RETURN V_SENT;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            LOG_ERR_TABLE_AND_JSON(V_SQLERR => 'No mobile found for employee ID: ' || P_EMP_ID, L_COMP_DESC => 'sms_pkg.send_court_session_notification'
            ,
                                  OUTPUT_JSON => FALSE);

            RETURN 0;
        WHEN OTHERS THEN
            LOG_ERR_TABLE_AND_JSON(V_SQLERR => SQLERRM, L_COMP_DESC => 'sms_pkg.send_court_session_notification',
                                  OUTPUT_JSON => FALSE);
            RETURN 0;
    END SEND_COURT_SESSION_NOTIFICATION;
---------------------------------------------------------------
-- ASHARIF 2025-12-06
-- Function: ENQUEUE_SMS
-- Purpose: Insert a new SMS into SMS_Q with audit fields and return generated SMS_ID

    FUNCTION ENQUEUE_SMS (
        P_SMS_TXT      IN VARCHAR2,               -- SMS message text
        P_SMS_TO       IN VARCHAR2,               -- Recipient mobile number
        P_CREATED_FROM IN VARCHAR2 DEFAULT NULL   -- Optional origin info (e.g., module, page)
    ) RETURN NUMBER IS
        V_SMS_ID NUMBER;                          -- Holds generated SMS_ID
    BEGIN
    -- Validation: SMS text must not be null
        IF P_SMS_TXT IS NULL THEN
            RAISE_APPLICATION_ERROR(-20001, 'SMS text cannot be null');
        END IF;

    -- Validation: Recipient number must be at least 11 characters
        IF LENGTH(P_SMS_TO) < 11 THEN
            RAISE_APPLICATION_ERROR(-20002, 'Recipient number must be at least 11 characters');
        END IF;


    -- Insert new SMS into queue
        INSERT INTO SMS_Q (
            SMS_TXT,
            SMS_TO,
            CREATED_AT,
            CREATED_BY,
            CREATED_FROM
        ) VALUES (
            P_SMS_TXT,
            P_SMS_TO,
            SYSDATE,                              -- Timestamp of enqueue
            V('APP_USER'),                        -- Current APEX user
            P_CREATED_FROM                        -- Optional origin
        ) RETURNING SMS_ID INTO V_SMS_ID;           -- Capture generated identity value

        RETURN V_SMS_ID;                          -- Return SMS_ID to caller

    EXCEPTION
        WHEN OTHERS THEN
        -- Log error with full context for traceability
            LOG_ERRORS(P_ERROR_MESSAGE => SQLERRM, P_ERROR_CODE => SQLCODE,
                      P_ERROR_STACK => DBMS_UTILITY.FORMAT_ERROR_BACKTRACE, P_CALLING_PROC => 'SMS_PKG.ENQUEUE_SMS ->' || P_SMS_TO ||
                      ' -> ' || P_SMS_TXT || ' -> ' || P_CREATED_FROM);

            RETURN 0;
    END ENQUEUE_SMS;
---------------------------------------------------------------

-- ASHARIF 2025-12-06
-- Procedure: RUN_SMS_Q
-- Purpose: Process unsent SMS messages in SMS_Q (IS_SENT=0).
--          Sends each SMS via SEND_SINGLE and marks as sent if successful.
--          Should be run in automation/background job.

    PROCEDURE RUN_SMS_Q IS
        V_RES NUMBER;                             -- Result flag from SEND_SINGLE
    BEGIN
    -- Loop through all unsent SMS messages
        FOR I IN (
            SELECT
                *
            FROM
                SMS_Q
            WHERE
                IS_SENT = 0
        ) LOOP
            BEGIN
                V_RES := 0;

            -- Attempt to send SMS using helper procedure
                V_RES := SMS_PKG.SEND_SINGLE(MSG => I.SMS_TXT, MOBILE => I.SMS_TO);
            -- If send successful (return code = 1), mark as sent
                IF V_RES = 1 THEN
                    UPDATE SMS_Q
                    SET
                        IS_SENT = 1
                    WHERE
                        SMS_ID = I.SMS_ID;

                    COMMIT;                        -- Commit after each successful send
                    APEX_AUTOMATION.LOG_INFO(P_MESSAGE => 'SMS SENT ID: ' || I.SMS_ID);
                ELSE
                    APEX_AUTOMATION.LOG_INFO(P_MESSAGE => 'ERRO SENDING SMS  ID: ' || I.SMS_ID);
                END IF;

            EXCEPTION
                WHEN OTHERS THEN
                -- Log error with SMS_ID context
                    LOG_ERRORS(P_ERROR_MESSAGE => SQLERRM, P_ERROR_CODE => SQLCODE,
                              P_ERROR_STACK => DBMS_UTILITY.FORMAT_ERROR_BACKTRACE, P_CALLING_PROC => 'SMS_PKG.RUN_SMS_Q ->' || I.SMS_ID
                              );
            END;
        END LOOP;
    END RUN_SMS_Q;

---------------------------------------------------------------
---------------------------------------------------------------
---------------------------------------------------------------

---------------------------------------------------------------
---------------------------------------------------------------
END SMS_PKG;
/
