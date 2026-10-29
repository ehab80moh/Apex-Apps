
  CREATE OR REPLACE FORCE EDITIONABLE VIEW "HQ_ELEVATED"."XXAPEX_HR_EMP_FINGER_PRINT" ("EMP_NUMBER", "FULL_NAME", "FIN_PROJECT", "SITE_CODE", "GDEP", "CHECK_IN_DATE", "CHECK_OUT_DATE", "SHIFT_DATES") AS
  SELECT
    las.emp_number,
    las.full_name,
    las.fin_project,
    las.site_code,
    las.gdep,
    MIN(
        CASE
            WHEN finger_print_typ = 'In' THEN
                las.check_date
            ELSE
                NULL
        END
    ) check_in_date,
    MAX(
        CASE
            WHEN finger_print_typ = 'Out' THEN
                las.check_date
            ELSE
                NULL
        END
    ) check_out_date,
     TRUNC(las.check_date) SHIFT_DATES
    -- WE SHOULD REPLASE CHECK DATE WITH SHIFT CASUSE IN SHIFT SOME EMPLOYEE MAY BE BETWEEN 2 DAYS THIER SHIFT;
FROM
    (
        SELECT
            emp.emp_number,
            asd.full_name,
            emp.fin_project,
            emp.site_code,
            nvl(asd.gdep,nvl(asd.project,'غير مسكن')) gdep,
            decode(tra.type, 'true', 'Out', 'In') finger_print_typ,
            to_char(tra.date_, 'HH24:MI:SS')      time_check,
            to_char(tra.date_, 'DD-MM-YYYY')      day_check,
            tra.date_                             check_date
        FROM
            central.xxapex_hr_emp_data         emp,
            hq_elevated.tms_emp_transactions   tra,
            central.xxapex_ss_emp_managers_asd asd
        WHERE
                1 = 1
            AND tra.employeenumber = emp.emp_number
            AND asd.employee_number = emp.emp_number
        UNION
        SELECT
            emp.emp_number,
            asd.full_name,
            emp.fin_project,
            emp.site_code,
            nvl(asd.gdep,nvl(asd.project,'غير مسكن')) gdep,
            decode(tra.type, 'true', 'Out', 'In') finger_print_typ,
            to_char(tra.date_, 'HH24:MI:SS')      time_check,
            to_char(tra.date_, 'DD-MM-YYYY')      day_check,
            tra.date_                             check_date
        FROM
            central.xxapex_hr_emp_data          emp,
            hq_elevated.tms_emp_transactions    tra,
            central.xxapex_ss_emp_managers_nadp asd
        WHERE
                1 = 1
            AND tra.employeenumber = emp.emp_number
            AND asd.employee_number = emp.emp_number
            AND emp.emp_number NOT IN (
                SELECT
                    aas.employee_number
                FROM
                    central.xxapex_ss_emp_managers_asd aas
            )
        UNION
        SELECT
            emp.emp_number,
            asd.full_name,
            emp.fin_project,
            emp.site_code,
            nvl(asd.gdep,nvl(asd.project,'غير مسكن')) gdep,
            decode(tra.type, 'true', 'Out', 'In') finger_print_typ,
            to_char(tra.date_, 'HH24:MI:SS')      time_check,
            to_char(tra.date_, 'DD-MM-YYYY')      day_check,
            tra.date_                             check_date
        FROM
            central.xxapex_hr_emp_data       emp,
            hq_elevated.tms_emp_transactions tra,
            central.xxapex_ss_emp_managers   asd
        WHERE
                1 = 1
            AND tra.employeenumber = emp.emp_number
            AND asd.employee_number = emp.emp_number
            AND emp.emp_number NOT IN (
                SELECT
                    aas.employee_number
                FROM
                    central.xxapex_ss_emp_managers_asd aas
                UNION
                SELECT
                    aas1.employee_number
                FROM
                    central.xxapex_ss_emp_managers_nadp aas1
            )
    ) las
WHERE
    1 = 1
GROUP BY
    las.emp_number,
    las.full_name,
    las.fin_project,
    las.site_code,
    las.gdep,
    TRUNC(las.check_date)
    -- WE SHOULD REPLASE CHECK DATE WITH SHIFT CASUSE IN SHIFT SOME EMPLOYEE MAY BE BETWEEN 2 DAYS THIER SHIFT;
