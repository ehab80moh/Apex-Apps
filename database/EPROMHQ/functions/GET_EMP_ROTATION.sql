
  CREATE OR REPLACE EDITIONABLE FUNCTION "EPROMHQ"."GET_EMP_ROTATION"
(
  P_EMP_ID IN VARCHAR2
, P_DATE IN DATE
) RETURN VARCHAR2 AS
v_rot varchar2(99);
BEGIN
select "work_type"
into v_rot
from tms_emp_rotation_plans
where employeenumber=p_emp_id
and date_= trunc(p_date);

--Standard	1
-- ERC New Standard	3167
-- Ramadan	2011
--RAMADAN 22	3233

return v_rot  ;

EXCEPTION
  WHEN OTHERS THEN

 RETURN NULL;
END GET_EMP_ROTATION;
/
