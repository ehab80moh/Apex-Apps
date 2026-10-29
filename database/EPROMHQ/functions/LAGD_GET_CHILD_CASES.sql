
  CREATE OR REPLACE EDITIONABLE FUNCTION "EPROMHQ"."LAGD_GET_CHILD_CASES"
(
  p_PARENT_CASE_ID IN VARCHAR2
) RETURN VARCHAR2 AS
l_cases varchar2(999);
BEGIN
SELECT LISTAGG(case_actual_number, ',') WITHIN GROUP (ORDER BY case_actual_number) AS case_numbers
into l_cases
FROM lagd_cases
WHERE parent_case_id = p_PARENT_CASE_ID;

  RETURN l_cases;
END LAGD_GET_CHILD_CASES;
/
