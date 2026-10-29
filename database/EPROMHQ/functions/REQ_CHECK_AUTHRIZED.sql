
  CREATE OR REPLACE EDITIONABLE FUNCTION "EPROMHQ"."REQ_CHECK_AUTHRIZED"
(p_user in VARCHAR2,p_page in VARCHAR2)
return BOOLEAN
is
V_COUNT NUMBER;
BEGIN
--return true;
SELECT COUNT(*) into  V_COUNT from REQ_ROLE_PAGE , REQ_USERS
where REQ_ROLE_PAGE.ROLE_ID = REQ_USERS.ROLE_ID
and
   UPPER(REQ_USERS.USER_NAME) LIKE UPPER(P_user)
   and  PAGE_ID  LIKE p_page ;
    IF V_COUNT > 0
        then
        return true;
        else
        return false;
    end if;
end;
/
