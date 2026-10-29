
  CREATE OR REPLACE EDITIONABLE PACKAGE "EPROMHQ"."SUP_OTP_PKG" is
  procedure generate_and_send_otp(p_supplier_id in number, p_mobile in varchar2);
  function verify_otp(p_supplier_id in number, p_otp in varchar2) return boolean;
end sup_otp_pkg;
/
