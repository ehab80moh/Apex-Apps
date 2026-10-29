
  CREATE OR REPLACE EDITIONABLE FUNCTION "EPROMHQ"."GET_FIRST_WORKING_DAY_OF_NEXT_MONTH" (
    p_date IN DATE
) RETURN DATE AS
    v_actual_first_day DATE;
BEGIN
--    v_actual_first_day := trunc(add_months(p_date, 1), 'MM');
--    FOR i IN 0..30 LOOP
--        IF to_char(v_actual_first_day + i, 'dy') NOT IN ( 'fri', 'sat' ) THEN
--            RETURN v_actual_first_day + i;
--        END IF;
--    END LOOP;
-- return central.XXAPEX_SS_VALIDATIONS.GET_CUT_DATE(p_date);

null;
--    RETURN NULL;
END get_first_working_day_of_next_month;
/
