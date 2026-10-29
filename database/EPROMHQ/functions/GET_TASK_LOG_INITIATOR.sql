
  CREATE OR REPLACE EDITIONABLE FUNCTION "EPROMHQ"."GET_TASK_LOG_INITIATOR"
(
  P_TASK_ID IN VARCHAR2
) RETURN VARCHAR2 AS
v_init varchar2(99);
BEGIN
select initiator into v_init from epromhq.TASK_FULL_DETAILS_LOG
where task_id=replace(central.GET_LAST_STRING(P_TASK_ID, '->'),'->','')
FETCH NEXT 1 ROWS ONLY;

  RETURN v_init;
exception when others then  return null;


END GET_TASK_LOG_INITIATOR;
/
