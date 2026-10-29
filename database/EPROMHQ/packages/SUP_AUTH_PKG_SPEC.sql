
  CREATE OR REPLACE EDITIONABLE PACKAGE "EPROMHQ"."SUP_AUTH_PKG" as
 function authenticate_supplier (
    p_username   in varchar2,
    p_password  in varchar2
  )return boolean;

end sup_auth_pkg;
/
