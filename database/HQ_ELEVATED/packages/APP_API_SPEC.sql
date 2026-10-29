
  CREATE OR REPLACE EDITIONABLE PACKAGE "HQ_ELEVATED"."APP_API" AS
----------------------------------------------------------------------------
    PROCEDURE check_api_key (
        p_api_key VARCHAR2
    );
----------------------------------------------------------------------------
    function is_api_key_valid(
        p_api_key VARCHAR2
    ) return number;
----------------------------------------------------------------------------
    PROCEDURE get_phone_concealed (
        p_emp_id VARCHAR2
    );
----------------------------------------------------------------------------

procedure get_otp(
p_username varchar2,
p_password varchar2
);

----------------------------------------------------------------------------
procedure real_login(
p_username varchar2,
p_password varchar2,
p_OTP varchar2
);

----------------------------------------------------------------------------
procedure   reset_otp(
p_emp_id varchar2,
p_phone varchar2
);
----------------------------------------------------------------------------
procedure   reset_password(
p_emp_id varchar2,
p_OTP varchar2,
p_password varchar2
);
----------------------------------------------------------------------------
procedure   emp_card(
p_token varchar2
);
----------------------------------------------------------------------------
----------------------------------------------------------------------------
END app_api;
/
