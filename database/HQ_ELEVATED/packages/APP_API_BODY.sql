
  CREATE OR REPLACE EDITIONABLE PACKAGE BODY "HQ_ELEVATED"."APP_API" AS

----------------------------------------------------------------------------
    PROCEDURE check_api_key (
        p_api_key VARCHAR2
    ) AS
    BEGIN
        IF p_api_key <> 'KAREEM_NAGGAR_SHERIF_SHARKAWY' THEN
            raise_application_error(-20403, 'app error');
        END IF;
    END check_api_key;
----------------------------------------------------------------------------
    function is_api_key_valid(
        p_api_key VARCHAR2
    ) return number
    as
    begin
IF p_api_key = 'KAREEM_NAGGAR_SHERIF_SHARKAWY' THEN
           return 1;
        END IF;
        return 0;
        exception WHEN others then return 0;
    END is_api_key_valid;
----------------------------------------------------------------------------
    PROCEDURE get_phone_concealed (
        p_emp_id VARCHAR2
    ) AS
        v_mobile VARCHAR2(99);
    BEGIN
        v_mobile := central.sms_pkg.get_emp_mobile(p_emp => p_emp_id, p_confirmed => 0);
v_mobile :=SUBSTR(v_mobile, 1,3) || '*****' || SUBSTR(v_mobile, -3);
        apex_json.open_object;
        apex_json.write('msg', v_mobile);
        apex_json.close_object;
    END get_phone_concealed;
----------------------------------------------------------------------------
-- get OTP via username and password returns 1 and await for OTP to do real login
procedure get_otp(
p_username varchar2,
p_password varchar2
)
as
   L_res NUMBER;
   v_ok boolean;
   v_msg varchar2(250);
BEGIN
   L_res := central.THROTTELE_FAILD_OTP(p_username);
----check otp throttle
   IF L_res = 1 THEN
       raise_application_error(-20403, 'تم إغلاق الحساب مؤقتًا بعد تجاوز عدة محاولات فاشلة للدخول');
   END IF;
--check username and password
  v_ok := central.AUTH_EMP(
    P_USERNAME => P_USERNAME,
    P_PASSWORD => P_PASSWORD
    );
--send otp
if v_ok then
V_MSG:=  central.SMS_PKG.SEND_OTP(
    P_USER => P_USERNAME,
    P_PASS => P_PASSWORD);
else
raise_application_error(-20403,  'اسم مستخدم او كلمة سر خطأ');
end if;

        apex_json.open_object;
        apex_json.write('msg', v_msg);
        apex_json.close_object;
end get_otp;
----------------------------------------------------------------------------
procedure real_login(
p_username varchar2,
p_password varchar2,
p_OTP varchar2
)
as
   v_ok boolean;
v_token varchar2(99);
begin
--check username and password again
  v_ok := central.AUTH_EMP(
    P_USERNAME => P_USERNAME,
    P_PASSWORD => P_PASSWORD
    );
--send otp
if not v_ok then
raise_application_error(-20403,  'اسم مستخدم او كلمة سر خطأ');
end if;

--check OTP
IF  Central.sms_pkg.check_otp(P_USERNAME,P_OTP) =1 then
v_token := central.REFRESH_EMP_TOKEN(P_USERNAME);
else
raise_application_error(-20403,  'الكود خطأ او تم انتهاء مدة صلاحيته ');
end if;



        apex_json.open_object;
        apex_json.write('msg', v_token);
        apex_json.close_object;
end real_login;
----------------------------------------------------------------------------
procedure   reset_otp(
p_emp_id varchar2,
p_phone varchar2
)
as
v_sent number;
v_mobile VARCHAR2(99);
    BEGIN
v_mobile := central.sms_pkg.get_emp_mobile(p_emp => p_emp_id, p_confirmed => 0);
-- check phone is correct
if v_mobile <> nvl(p_phone,0) then
raise_application_error(-20403,  'رقم الهاتف المدخل غير مطابق');
end if;
--send reset code
 v_sent :=    central.SMS_PKG.SEND_RESET_CODE(
    P_USER => p_emp_id
  );
  if v_sent <>1 then
raise_application_error(-20403, 'يوجد خطأ ما في ارسال الرسالة'    );
  end if;

apex_json.open_object;
apex_json.write('msg', 'success');
apex_json.close_object;

end reset_otp;
----------------------------------------------------------------------------
procedure   reset_password(
p_emp_id varchar2,
p_OTP varchar2,
p_password varchar2
)
as
v_code varchar2(99);
begin
-- check reset code
v_code := central.GET_EMP_REST_CODE( p_emp_id );

IF V_CODE IS NULL or trim(v_code)<> trim(p_OTP) THEN
raise_application_error(-20403,  'الكود خطأ او تم انتهاء مدة صلاحيته ');
END IF;

  central.UPDATE_EMP_PASSWORD(
    P_EMP_ID => p_emp_id,
    P_NEW_PASS => p_password
  );

apex_json.open_object;
apex_json.write('msg', 'success');
apex_json.close_object;

end reset_password;

----------------------------------------------------------------------------
procedure   emp_card(
p_token varchar2
) as
v_emp_id varchar2(99);
l_output varchar2(4000);
begin

v_emp_id := central.GET_EMP_BY_TOKEN(p_token);
IF v_emp_id = '0' THEN
raise_application_error(-20403, 'invalid token' );
END IF;
SELECT JSON_OBJECT(
    'id' VALUE emp_number,
    'name' VALUE emp_name,
    'org' VALUE organization_name,
    'pos' VALUE excel_pos,
    'image' VALUE 'https://apex.eprom.com.eg/apex/hq_elevated/app/empimage?empid='||emp_number
) AS json_output
into l_output
FROM central.xxapex_hr_emp_data
where emp_number= central.GET_EMP_BY_TOKEN(p_token)
;
 owa_util.mime_header('application/json', FALSE);
htp.p(chr(10)); -- new line
htp.p(l_output);

end emp_card;
----------------------------------------------------------------------------
----------------------------------------------------------------------------
----------------------------------------------------------------------------

END app_api;
/
