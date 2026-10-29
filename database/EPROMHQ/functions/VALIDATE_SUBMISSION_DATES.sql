
  CREATE OR REPLACE EDITIONABLE FUNCTION "EPROMHQ"."VALIDATE_SUBMISSION_DATES" (
   p_from_date IN DATE,
   p_to_date   IN DATE
) RETURN VARCHAR2
IS
  l_day date;
  v_count3 number;
  V_EMP_PLAN_TYPE VARCHAR2(99):='Day';
BEGIN
 FOR i IN 0..(p_to_date - p_from_date)
   LOOP
     l_day:= p_from_date+i;

     if to_char(l_day, 'DY') IN ( 'FRI', 'SAT' ) then
DBMS_OUTPUT.PUT_LINE(l_day);
end if;

  SELECT
                COUNT(*)
            INTO v_count3
            FROM
                central.xxapex_eprom_holiday
            WHERE
                    1 = 1
                AND holiday_date = l_day;

            IF
                ( to_char(l_day, 'DY') IN ( 'FRI', 'SAT' ) OR v_count3 > 0 )
                AND v_emp_plan_type = 'Day'
            THEN --غير مسموع بإذن شخصي في ايام توقف العمل
                RETURN '5lsy b2aaa';
--                apex_lang.message('XX_SS_CHECK_PERM_5', p_application_id => 115);
            END IF;
      end loop;

  return 1;
END;
/
