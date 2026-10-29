
  CREATE OR REPLACE EDITIONABLE PACKAGE BODY "EPROMHQ"."SUP_OTP_PKG" is

  -- generate 4-digit numeric OTP
  function random_otp return varchar2 is
  begin
    return lpad(trunc(dbms_random.value(0, 10000)), 4, '0');
  end;

  /*procedure send_sms(p_mobile in varchar2, p_message in varchar2) is
  begin
    -- later you can replace this with Twilio or another API
    apex_debug.message('SMS to %s: %s', p_mobile, p_message);
  end;*/
procedure send_sms(p_mobile in varchar2, p_message in varchar2) is
  l_result varchar2(4000);
begin
  -- Call the FUNCTION and capture result
  l_result := central.sms_pkg.send_single(
                p_message,
                p_mobile
              );

  -- Optional: log result for debugging
  apex_debug.message('SMS Result: %s', l_result);

end;

procedure generate_and_send_otp(p_supplier_id in number, p_mobile in varchar2) is
  l_otp_count number;
  l_otp       varchar2(10);
  l_exp       timestamp;
begin
  -- Count how many OTPs were generated today
  select count(*)
    into l_otp_count
    from sup_otps
   where supplier_id = p_supplier_id
     and trunc(created_on) = trunc(sysdate);

  if l_otp_count >= 4 then
    -- Do NOT generate a new OTP
    send_sms(p_mobile,
      'You have already received "4" OTP codes today. Please use your last OTP. ' ||
      'You can request a new code tomorrow.');
    return;
  end if;

  -- Invalidate previous OTPs (only if limit not reached)
  update sup_otps
     set used_flag = 'Y'
   where supplier_id = p_supplier_id
     and used_flag = 'N';
  commit;

  -- Generate new OTP
  l_otp := random_otp;
  l_exp := systimestamp + numtodsinterval(60, 'minute'); -- 60 min expiry

  insert into sup_otps (supplier_id, otp_code, expires_on)
  values (p_supplier_id, l_otp, l_exp);

  commit;

  -- Send SMS (or log message)
  send_sms(p_mobile,
--    'Your verification is' || l_otp );
--    'Your verification code is: ' || l_otp || ' (valid for 60 minutes)');
    'Your verification is: ' || l_otp || ' (valid for 60 minutes)');

end generate_and_send_otp;


  function verify_otp(p_supplier_id in number, p_otp in varchar2) return boolean is
    l_row sup_otps%rowtype;
  begin
    select *
      into l_row
      from sup_otps
     where supplier_id = p_supplier_id
       and used_flag = 'N'
     order by created_on desc
     fetch first 1 row only;

    if l_row.expires_on < systimestamp then
      update sup_otps set used_flag = 'Y' where otp_id = l_row.otp_id;
      commit;
      return false;
    end if;

    if l_row.attempt_count > 4 then
      return false;
    end if;

    if l_row.otp_code = p_otp then
      update sup_otps set used_flag = 'Y' where otp_id = l_row.otp_id;
      update sup_suppliers
         set status = 'ACTIVE',
             activated_on = systimestamp
       where supplier_id = p_supplier_id;
      commit;
      return true;
    else
      update sup_otps
         set attempt_count = attempt_count + 1
       where otp_id = l_row.otp_id;
      commit;
      return false;
    end if;
  exception
    when no_data_found then
      return false;
  end verify_otp;

end sup_otp_pkg;
/
