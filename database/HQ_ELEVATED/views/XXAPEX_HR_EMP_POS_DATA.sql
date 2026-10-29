
  CREATE OR REPLACE FORCE EDITIONABLE VIEW "HQ_ELEVATED"."XXAPEX_HR_EMP_POS_DATA" ("EMP_NUMBER", "FULL_NAME", "FIN_PROJECT", "SITE_CODE", "GDEP") AS
  SELECT
            emp.emp_number,
            asd.full_name,
            emp.fin_project,
            emp.site_code,
            nvl(asd.gdep,nvl(asd.project,'غير مسكن')) gdep

        FROM
            central.xxapex_hr_emp_data         emp,

            central.xxapex_ss_emp_managers_asd asd
        WHERE
                1 = 1
            AND asd.employee_number = emp.emp_number
        UNION
        SELECT
            emp.emp_number,
            asd.full_name,
            emp.fin_project,
            emp.site_code,
            nvl(asd.gdep,nvl(asd.project,'غير مسكن')) gdep
        FROM
            central.xxapex_hr_emp_data          emp,
            central.xxapex_ss_emp_managers_nadp asd
        WHERE
                1 = 1
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
            nvl(asd.gdep,nvl(asd.project,'غير مسكن')) gdep
        FROM
            central.xxapex_hr_emp_data       emp,
            central.xxapex_ss_emp_managers   asd
        WHERE
                1 = 1
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
            );
