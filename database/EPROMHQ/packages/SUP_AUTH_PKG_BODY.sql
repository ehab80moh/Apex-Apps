
  CREATE OR REPLACE EDITIONABLE PACKAGE BODY "EPROMHQ"."SUP_AUTH_PKG" as

  function authenticate_supplier (
    p_username   in varchar2,
    p_password  in varchar2
  ) return boolean
  is
    l_hash        varchar2(4000);
    l_db_hash     varchar2(4000);
    l_supplier_id number;
  begin
    -- Try to find supplier
    select supplier_id, password_hash
      into l_supplier_id, l_db_hash
      from sup_suppliers
     where headoff_mobile = p_username;

    -- Hash entered password
    l_hash := rawtohex(
                dbms_crypto.hash(
                  utl_raw.cast_to_raw(p_password),
                  dbms_crypto.hash_sh256)
              );

    -- Compare hashes
    if l_hash = l_db_hash then
      -- Optional: update login tracking
      update sup_suppliers
         set last_login_on = systimestamp
       where supplier_id = l_supplier_id;

      -- Set supplier_id in APEX session
--      apex_util.set_session_state('P17_SUPPLIER_ID', l_supplier_id);

      return true;
    else
      return false;
    end if;

  exception
    when no_data_found then
      return false;
    when others then
      -- avoid leaking internal errors
      return false;
  end authenticate_supplier;


end sup_auth_pkg;
/
