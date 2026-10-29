
  CREATE OR REPLACE EDITIONABLE FUNCTION "HQ_ELEVATED"."SEARCH_DELIMETED_STRING"
(
  P_STRING IN VARCHAR2
, P_DELIMITER IN VARCHAR2 default ':'
, P_SEARCH IN VARCHAR2
) RETURN NUMBER AS
cursor cr is
select column_value val from table(apex_string.split(P_STRING,P_DELIMITER))
;

BEGIN

for c in cr loop
if c.val = p_search then
return 1;
end if;
end loop;


  RETURN 0;
END SEARCH_DELIMETED_STRING;
/
