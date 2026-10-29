
  CREATE OR REPLACE EDITIONABLE PROCEDURE "EPROMHQ"."SUP_OTP_EXPIRE_DAILY" is
begin
  update sup_otps
     set used_flag = 'Y'
   where used_flag = 'N'
     and trunc(created_on) < trunc(sysdate);

  commit;

end sup_otp_expire_daily;
/
