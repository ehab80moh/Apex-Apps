
  CREATE OR REPLACE EDITIONABLE FUNCTION "HQ_ELEVATED"."GET_PASSED_LIMIT_DATA" (
    p_year   IN NUMBER,
    p_ismidor IN NUMBER
) RETURN SYS_REFCURSOR
AS
    rc SYS_REFCURSOR;
BEGIN
    OPEN rc FOR
   SELECT
    'file1' AS "filename",
    CURSOR(
        WITH Params AS (
            SELECT
                :P_YEAR AS YEAR,
                TO_DATE(:P_YEAR || '-01-01','YYYY-MM-DD') AS START_DATE,
                TO_DATE(:P_YEAR || '-12-31','YYYY-MM-DD') AS END_DATE,
                :P_ISMIDOR AS ISMIDOR
            FROM DUAL
        ),
        MaxPeriodsOfService AS (
            SELECT person_id, TRUNC(MAX(date_start)) AS max_start_date
            FROM   hr_per_periods_of_service
            GROUP  BY person_id
        ),
        LatestPersonData AS (
            SELECT person_id, actual_termination_date AS term_date, leaving_reason, date_start
            FROM   hr_per_periods_of_service p
            WHERE  (p.person_id, p.date_start) IN (
                     SELECT person_id, MAX(date_start)
                     FROM   hr_per_periods_of_service
                     GROUP  BY person_id
                   )
        ),
        LatestAssignment AS (
            SELECT a.*
            FROM   hr_per_all_assignments_f a
            WHERE  a.effective_end_date = (
                     SELECT MAX(a2.effective_end_date)
                     FROM   hr_per_all_assignments_f a2
                     WHERE  a2.person_id = a.person_id
                   )
        ),
        EmpProjectBase AS (
            SELECT
                papf.employee_number AS EMP_ID,
                NVL(pap.payroll_id, 0) AS PAYROLL_ID,
                mea.meaning AS PAYROLL_NAME,
                las.effective_start_date,
                las.effective_end_date,
                CASE WHEN ppts.user_person_type LIKE '%Ex-employee%' THEN lpd.leaving_reason ELSE NULL END AS LEAVING_REASON,
                CASE WHEN ppts.user_person_type LIKE '%Ex-employee%' THEN lpd.term_date ELSE NULL END AS ACTUAL_TERMINATION_DATE,
                papf.person_id,
                papf.person_type_id,
                papf.full_name
            FROM   hr_per_all_people_f papf
            JOIN   hr_per_person_types  ppts ON ppts.person_type_id = papf.person_type_id
            LEFT JOIN LatestAssignment  las  ON las.person_id       = papf.person_id
            LEFT JOIN hr_pay_people_groups ppg ON ppg.people_group_id = las.people_group_id
            LEFT JOIN XX_EPROM_PROJECT_MEDICAL mea ON mea.lookup_code = ppg.segment2
            LEFT JOIN payroll_group_mapping pap ON pap.group_name = mea.meaning
            LEFT JOIN MaxPeriodsOfService mps ON mps.person_id = papf.person_id
            LEFT JOIN LatestPersonData lpd ON lpd.person_id = papf.person_id
            WHERE  papf.person_type_id IN (1123,1120,1121)
              AND  SYSDATE BETWEEN papf.effective_start_date AND papf.effective_end_date
              AND  ( lpd.date_start IS NULL OR TRUNC(lpd.date_start) = mps.max_start_date )
        ),
MaxAssignmentDates AS (
    SELECT person_id, MAX(effective_start_date) AS max_date
    FROM hr_per_all_assignments_f
    GROUP BY person_id
),
MaxPeriodsOfServiceDates AS (
    SELECT person_id, MAX(date_start) AS max_service_date
    FROM hr_per_periods_of_service
    GROUP BY person_id
),
EmpBase AS (
    SELECT
        papf.person_id,
        papf.employee_number AS EMP_ID,
        papf.full_name,
        PER.ACTUAL_TERMINATION_DATE AS ACTUAL_TERMINATION_DATE,
        CASE
            WHEN SYSDATE BETWEEN PER.DATE_START AND PER.ACTUAL_TERMINATION_DATE THEN NULL
            ELSE pass.service_leaving_res
        END AS LEAVING_REASON
    FROM hr_per_all_people_f papf
    JOIN MaxAssignmentDates MAD ON papf.person_id = MAD.person_id
    JOIN MaxPeriodsOfServiceDates MPSD ON papf.person_id = MPSD.person_id
    LEFT JOIN hr_per_all_assignments_f pass
           ON pass.person_id = MAD.person_id AND pass.effective_start_date = MAD.max_date
    LEFT JOIN hr_per_periods_of_service PER
           ON PER.person_id = MPSD.person_id AND PER.date_start = MPSD.max_service_date
    WHERE papf.person_type_id IN (1123, 1120, 1121)
      AND TRUNC(SYSDATE) BETWEEN papf.effective_start_date AND papf.effective_end_date
),

/* ===== CLAIM_PERSON_VIEW REPLACEMENT ===== */
ClaimBase AS (
  SELECT
      CPS.ID,
      CL.ID AS CLAIM_ID,
      CPS.EMPLOYEE_NUMBER,
      CPS.PERSON_ID,
      CPS.COVERED,
      CPS.NOT_COVERED,
      CPS.PATIENT_TYPE,
      CPS.INVOICE_DATE,
      CASE WHEN EP.ACTUAL_TERMINATION_DATE > CPS.INVOICE_DATE THEN EP.PAYROLL_ID
           ELSE NVL(NVL2(EP.ACTUAL_TERMINATION_DATE,0,EP.PAYROLL_ID),0)
      END AS PAYROLL_ID,
      EP.PAYROLL_NAME
  FROM MD_CLAIM_PERSON_SUMMARY CPS
  JOIN MD_CLAIM CL ON CL.ID = CPS.MD_CLAIM_ID
  LEFT JOIN EmpProjectBase EP ON EP.EMP_ID = CPS.EMPLOYEE_NUMBER
       AND CPS.INVOICE_DATE BETWEEN EP.EFFECTIVE_START_DATE AND EP.EFFECTIVE_END_DATE
),

/* ===== REFUND_PERSON_VIEW REPLACEMENT ===== */
RefundBase AS (
  SELECT
    rs.id,
    rs.EMPLOYEE_NUMBER,
    rs.PERSON_ID,
    rs.COVERED,
    rs.UNCOVERED,
    rs.REFUND_GROUP_ID,
    rs.REFUND_DATE,
    CASE WHEN ep.ACTUAL_TERMINATION_DATE > rs.REFUND_DATE THEN ep.payroll_id
         ELSE NVL(NVL2(ep.ACTUAL_TERMINATION_DATE,0,ep.payroll_id),0)
    END AS PAYROLL_ID,
    ep.PAYROLL_NAME
  FROM MD_REFUND_SUMMARY rs
  JOIN MD_REFUND_BATCH RB ON RB.ID = rs.BATCH_ID
  LEFT JOIN EmpProjectBase ep ON ep.EMP_ID = rs.EMPLOYEE_NUMBER
       AND rs.REFUND_DATE BETWEEN ep.EFFECTIVE_START_DATE AND ep.EFFECTIVE_END_DATE
),

/* ===== COMMITTEE_VIEW REPLACEMENT ===== */
CommitteeBase AS (
  SELECT
      mc.EMP_ID,
      mc.SUPPORT,
      mc.SUPPORT_DATE
  FROM MD_COMMITTEE mc
  JOIN MD_COMMITTEE_MASTER mcm ON mc.COMMITTEE_MASTER_ID = mcm.ID
  LEFT JOIN EmpProjectBase ep ON ep.EMP_ID = mc.EMP_ID
       AND mc.SUPPORT_DATE BETWEEN ep.EFFECTIVE_START_DATE AND ep.EFFECTIVE_END_DATE
  WHERE mc.COMMITTEE_MASTER_ID IS NOT NULL
),

/* ===== MIDOR EMPLOYEES ===== */
MidorEmployees AS (
    SELECT DISTINCT EMP_ID
    FROM EmpProjectBase ep
    CROSS JOIN Params p
    WHERE ((ep.EFFECTIVE_END_DATE >= p.END_DATE AND ep.EFFECTIVE_START_DATE < p.END_DATE)
           OR (ep.LEAVING_REASON = 'R' AND ep.EFFECTIVE_END_DATE >= p.START_DATE))
      AND ep.PAYROLL_ID IN (63,108,1008,1032)
),

/* ===== CLAIMS & REFUNDS ===== */
PersonalClaims AS (
    SELECT EMPLOYEE_NUMBER, PATIENT_TYPE, SUM(COVERED) AS COVERED, SUM(NVL(NOT_COVERED,0)) AS NOT_COVERED
    FROM ClaimBase c
    CROSS JOIN Params p
    WHERE c.PERSON_ID = 0
      AND c.CLAIM_ID IS NOT NULL
      AND c.INVOICE_DATE BETWEEN p.START_DATE AND p.END_DATE
      AND NOT (
           EXISTS (SELECT 1 FROM EmpBase ee WHERE ee.EMP_ID = c.EMPLOYEE_NUMBER AND ee.LEAVING_REASON = 'R')
           AND NVL(c.PAYROLL_ID,0) = 0
      )
    GROUP BY EMPLOYEE_NUMBER, PATIENT_TYPE
),
PersonalRefunds AS (
    SELECT EMPLOYEE_NUMBER, REFUND_GROUP_ID, SUM(COVERED) AS COVERED, SUM(NVL(UNCOVERED,0)) AS UNCOVERED
    FROM RefundBase r
    CROSS JOIN Params p
    WHERE r.PERSON_ID = 0
      AND r.REFUND_DATE BETWEEN p.START_DATE AND p.END_DATE
      AND NOT (
           EXISTS (SELECT 1 FROM EmpBase ee WHERE ee.EMP_ID = r.EMPLOYEE_NUMBER AND ee.LEAVING_REASON = 'R')
           AND NVL(r.PAYROLL_ID,0) = 0
      )
    GROUP BY EMPLOYEE_NUMBER, REFUND_GROUP_ID
),
FamilyClaims AS (
    SELECT EMPLOYEE_NUMBER, PATIENT_TYPE, SUM(COVERED) AS COVERED, SUM(NVL(NOT_COVERED,0)) AS NOT_COVERED,
           SUM(CASE WHEN PATIENT_TYPE = 20 THEN COVERED ELSE 0 END) AS COVID_COVERED
    FROM ClaimBase c
    CROSS JOIN Params p
    WHERE c.PERSON_ID != 0
      AND c.CLAIM_ID IS NOT NULL
      AND c.INVOICE_DATE BETWEEN p.START_DATE AND p.END_DATE
      AND NOT (
           EXISTS (SELECT 1 FROM EmpBase ee WHERE ee.EMP_ID = c.EMPLOYEE_NUMBER AND ee.LEAVING_REASON = 'R')
           AND NVL(c.PAYROLL_ID,0) = 0
      )
    GROUP BY EMPLOYEE_NUMBER, PATIENT_TYPE
),
FamilyRefunds AS (
    SELECT EMPLOYEE_NUMBER, REFUND_GROUP_ID, SUM(COVERED) AS COVERED, SUM(NVL(UNCOVERED,0)) AS UNCOVERED
    FROM RefundBase r
    CROSS JOIN Params p
    WHERE r.PERSON_ID != 0
      AND r.REFUND_DATE BETWEEN p.START_DATE AND p.END_DATE
      AND NOT (
           EXISTS (SELECT 1 FROM EmpBase ee WHERE ee.EMP_ID = r.EMPLOYEE_NUMBER AND ee.LEAVING_REASON = 'R')
           AND NVL(r.PAYROLL_ID,0) = 0
      )
    GROUP BY EMPLOYEE_NUMBER, REFUND_GROUP_ID
),

AllEmpIDs AS (
    SELECT EMPLOYEE_NUMBER AS EMP_ID FROM PersonalClaims
    UNION
    SELECT EMPLOYEE_NUMBER FROM PersonalRefunds
    UNION
    SELECT EMPLOYEE_NUMBER FROM FamilyClaims
    UNION
    SELECT EMPLOYEE_NUMBER FROM FamilyRefunds
),

Employees AS (
    SELECT e.EMP_ID, e.FULL_NAME, e.LEAVING_REASON, e.ACTUAL_TERMINATION_DATE
    FROM EmpBase e
    JOIN AllEmpIDs a ON e.EMP_ID = a.EMP_ID
    CROSS JOIN Params p
    WHERE (e.LEAVING_REASON IS NULL OR e.LEAVING_REASON != 'R'
           OR (e.LEAVING_REASON = 'R' AND e.ACTUAL_TERMINATION_DATE > p.START_DATE))
      AND ((p.ISMIDOR = 1 AND e.EMP_ID IN (SELECT EMP_ID FROM MidorEmployees))
           OR (p.ISMIDOR = 0 AND e.EMP_ID NOT IN (SELECT EMP_ID FROM MidorEmployees)))
),

LatestProject AS (
    SELECT *
    FROM (
        SELECT ep.EMP_ID, ep.PAYROLL_ID, ep.PAYROLL_NAME,
               ROW_NUMBER() OVER (PARTITION BY ep.EMP_ID ORDER BY ep.EFFECTIVE_END_DATE DESC) AS RN
        FROM EmpProjectBase ep
        JOIN Employees e ON ep.EMP_ID = e.EMP_ID
        WHERE ep.PAYROLL_ID IS NOT NULL
          AND ep.PAYROLL_ID != 1012
          AND ep.EFFECTIVE_START_DATE <= (SELECT END_DATE FROM Params)
          AND ep.EFFECTIVE_END_DATE >= (SELECT START_DATE FROM Params)
    ) WHERE RN = 1
),

Limits AS (
    SELECT EMP_ID, SUM(LIMIT) AS LIMIT_VALUE
    FROM MD_EMP_LIMIT
    WHERE YEAR = :P_YEAR
    GROUP BY EMP_ID
),
Supports AS (
    SELECT EMP_ID, SUM(SUPPORT) AS SUPPORT_VALUE
    FROM CommitteeBase
    WHERE EXTRACT(YEAR FROM SUPPORT_DATE) = :P_YEAR
    GROUP BY EMP_ID
),
Discounts AS (
    SELECT EMP_ID, SUM(AMOUNT) AS DISCOUNT_VALUE
    FROM MD_EMP_DISCOUNTS
    WHERE EXTRACT(YEAR FROM DISCOUNT_DATE) = :P_YEAR
    GROUP BY EMP_ID
),

/* ===== FAMILY & PERSONAL DENTAL DEDUCTIONS ===== */
FamilyDentalDeduction AS (
    SELECT e.EMP_ID,
           CASE
               WHEN :P_YEAR >= 2023 THEN
                    GREATEST(
                        NVL((SELECT SUM(COVERED) FROM FamilyClaims c WHERE c.EMPLOYEE_NUMBER = e.EMP_ID AND c.PATIENT_TYPE = 22),0) +
                        NVL((SELECT SUM(COVERED) FROM FamilyRefunds r WHERE r.EMPLOYEE_NUMBER = e.EMP_ID AND r.REFUND_GROUP_ID = 22),0) -
                        NVL((SELECT TO_NUMBER(esd.VALUE)
                             FROM MED.EFFECTIVE_SETTING es
                             JOIN MED.EFFECTIVE_SETTING_DETAILS esd ON es.ID = esd.EFFECTIVE_SETTING_ID
                             WHERE es.NAME = 'FamilyDentalLimit'
                               AND :P_YEAR BETWEEN EXTRACT(YEAR FROM esd.DATE_FROM) AND EXTRACT(YEAR FROM esd.DATE_TO)
                        ),0),
                        0
                    )
               ELSE
                    GREATEST(
                        NVL((SELECT SUM(COVERED) FROM FamilyClaims c WHERE c.EMPLOYEE_NUMBER = e.EMP_ID AND c.PATIENT_TYPE = 4),0) +
                        NVL((SELECT SUM(COVERED) FROM FamilyRefunds r WHERE r.EMPLOYEE_NUMBER = e.EMP_ID AND r.REFUND_GROUP_ID = 4),0) -
                        NVL((SELECT TO_NUMBER(esd.VALUE)
                             FROM MED.EFFECTIVE_SETTING es
                             JOIN MED.EFFECTIVE_SETTING_DETAILS esd ON es.ID = esd.EFFECTIVE_SETTING_ID
                             WHERE es.NAME = 'FamilyDentalWorkLimit'
                               AND :P_YEAR BETWEEN EXTRACT(YEAR FROM esd.DATE_FROM) AND EXTRACT(YEAR FROM esd.DATE_TO)
                        ),0),
                        0
                    )
                    +
                    GREATEST(
                        NVL((SELECT SUM(COVERED) FROM FamilyClaims c WHERE c.EMPLOYEE_NUMBER = e.EMP_ID AND c.PATIENT_TYPE = 6),0) +
                        NVL((SELECT SUM(COVERED) FROM FamilyRefunds r WHERE r.EMPLOYEE_NUMBER = e.EMP_ID AND r.REFUND_GROUP_ID = 6),0) -
                        NVL((SELECT TO_NUMBER(esd.VALUE)
                             FROM MED.EFFECTIVE_SETTING es
                             JOIN MED.EFFECTIVE_SETTING_DETAILS esd ON es.ID = esd.EFFECTIVE_SETTING_ID
                             WHERE es.NAME = 'FamilyDentalImplementationLimit'
                               AND :P_YEAR BETWEEN EXTRACT(YEAR FROM esd.DATE_FROM) AND EXTRACT(YEAR FROM esd.DATE_TO)
                        ),0),
                        0
                    )
           END AS DENTAL_FAMILY_DEDUCTION
    FROM Employees e
),
PersonalDentalDeduction AS (
    SELECT e.EMP_ID,
           CASE
               WHEN :P_YEAR >= 2023 THEN
                    GREATEST(
                        NVL((SELECT SUM(COVERED) FROM PersonalClaims c WHERE c.EMPLOYEE_NUMBER = e.EMP_ID AND c.PATIENT_TYPE = 22),0) +
                        NVL((SELECT SUM(COVERED) FROM PersonalRefunds r WHERE r.EMPLOYEE_NUMBER = e.EMP_ID AND r.REFUND_GROUP_ID = 22),0) -
                        NVL((SELECT TO_NUMBER(esd.VALUE)
                             FROM MED.EFFECTIVE_SETTING es
                             JOIN MED.EFFECTIVE_SETTING_DETAILS esd ON es.ID = esd.EFFECTIVE_SETTING_ID
                             WHERE es.NAME = 'PersonalDentalLimit'
                               AND :P_YEAR BETWEEN EXTRACT(YEAR FROM esd.DATE_FROM) AND EXTRACT(YEAR FROM esd.DATE_TO)
                        ),0),
                        0
                    )
               ELSE
                    GREATEST(
                        NVL((SELECT SUM(COVERED) FROM PersonalClaims c WHERE c.EMPLOYEE_NUMBER = e.EMP_ID AND c.PATIENT_TYPE = 4),0) +
                        NVL((SELECT SUM(COVERED) FROM PersonalRefunds r WHERE r.EMPLOYEE_NUMBER = e.EMP_ID AND r.REFUND_GROUP_ID = 4),0) -
                        NVL((SELECT TO_NUMBER(esd.VALUE)
                             FROM MED.EFFECTIVE_SETTING es
                             JOIN MED.EFFECTIVE_SETTING_DETAILS esd ON es.ID = esd.EFFECTIVE_SETTING_ID
                             WHERE es.NAME = 'PersonalDentalWorkLimit'
                               AND :P_YEAR BETWEEN EXTRACT(YEAR FROM esd.DATE_FROM) AND EXTRACT(YEAR FROM esd.DATE_TO)
                        ),0),
                        0
                    )
                    +
                    GREATEST(
                        NVL((SELECT SUM(COVERED) FROM PersonalClaims c WHERE c.EMPLOYEE_NUMBER = e.EMP_ID AND c.PATIENT_TYPE = 6),0) +
                        NVL((SELECT SUM(COVERED) FROM PersonalRefunds r WHERE r.EMPLOYEE_NUMBER = e.EMP_ID AND r.REFUND_GROUP_ID = 6),0) -
                        NVL((SELECT TO_NUMBER(esd.VALUE)
                             FROM MED.EFFECTIVE_SETTING es
                             JOIN MED.EFFECTIVE_SETTING_DETAILS esd ON es.ID = esd.EFFECTIVE_SETTING_ID
                             WHERE es.NAME = 'PersonalDentalImplementationLimit'
                               AND :P_YEAR BETWEEN EXTRACT(YEAR FROM esd.DATE_FROM) AND EXTRACT(YEAR FROM esd.DATE_TO)
                        ),0),
                        0
                    )
           END AS DENTAL_PERSONAL_DEDUCTION
    FROM Employees e
),

FamilyCovered AS (
    SELECT
        e.EMP_ID,
        NVL((SELECT SUM(COVERED) FROM FamilyClaims c WHERE c.EMPLOYEE_NUMBER = e.EMP_ID AND c.PATIENT_TYPE != 20),0) +
        NVL((SELECT SUM(COVERED)*0.75 FROM FamilyClaims c WHERE c.EMPLOYEE_NUMBER = e.EMP_ID AND c.PATIENT_TYPE = 20),0) +
        NVL((SELECT SUM(COVERED) FROM FamilyRefunds r WHERE r.EMPLOYEE_NUMBER = e.EMP_ID),0) AS FAMILY_COVERED
    FROM Employees e
),
FamilyDeductionCalc AS (
            SELECT
                e.EMP_ID,
                NVL(l.LIMIT_VALUE,0) AS LIMIT_VALUE,
                NVL(s.SUPPORT_VALUE,0) AS SUPPORT_VALUE,
                NVL(d.DISCOUNT_VALUE,0) AS DISCOUNT_VALUE,
                f.FAMILY_COVERED,
                (NVL(l.LIMIT_VALUE,0)+NVL(s.SUPPORT_VALUE,0)+NVL(d.DISCOUNT_VALUE,0)-f.FAMILY_COVERED) AS FAMILY_DEDUCTION,
                CASE
                    WHEN (NVL(l.LIMIT_VALUE,0)+NVL(s.SUPPORT_VALUE,0)+NVL(d.DISCOUNT_VALUE,0)-f.FAMILY_COVERED) >= 0 THEN 0
                    ELSE -(NVL(l.LIMIT_VALUE,0)+NVL(s.SUPPORT_VALUE,0)+NVL(d.DISCOUNT_VALUE,0)-f.FAMILY_COVERED)
                END AS USAGE_FAMILY_DEDUCTION
            FROM Employees e
            LEFT JOIN Limits l ON e.EMP_ID = l.EMP_ID
            LEFT JOIN Supports s ON e.EMP_ID = s.EMP_ID
            LEFT JOIN Discounts d ON e.EMP_ID = d.EMP_ID
            LEFT JOIN FamilyCovered f ON e.EMP_ID = f.EMP_ID
        )

        SELECT
            e.EMP_ID,
            e.FULL_NAME AS EMP_NAME,
            lp.PAYROLL_ID,
            lp.PAYROLL_NAME,
            NVL(l.LIMIT_VALUE,0) AS LIMIT,
            NVL(s.SUPPORT_VALUE,0) AS SUPPORT,
            NVL(d.DISCOUNT_VALUE,0) AS DISCOUNT,
            NVL((SELECT SUM(COVERED) FROM PersonalClaims c WHERE c.EMPLOYEE_NUMBER = e.EMP_ID),0) +
            NVL((SELECT SUM(COVERED) FROM PersonalRefunds r WHERE r.EMPLOYEE_NUMBER = e.EMP_ID),0) AS PERSONAL_COVERED,
            NVL((SELECT SUM(COVERED) FROM FamilyClaims c WHERE c.EMPLOYEE_NUMBER = e.EMP_ID),0) +
            NVL((SELECT SUM(COVERED) FROM FamilyRefunds r WHERE r.EMPLOYEE_NUMBER = e.EMP_ID),0) AS FAMILY_COVERED,
            NVL((SELECT SUM(NOT_COVERED) FROM PersonalClaims c WHERE c.EMPLOYEE_NUMBER = e.EMP_ID),0) +
            NVL((SELECT SUM(UNCOVERED) FROM PersonalRefunds r WHERE r.EMPLOYEE_NUMBER = e.EMP_ID),0) AS PERSONAL_NOT_COVERED,
            NVL((SELECT SUM(NOT_COVERED) FROM FamilyClaims c WHERE c.EMPLOYEE_NUMBER = e.EMP_ID),0) +
            NVL((SELECT SUM(UNCOVERED) FROM FamilyRefunds r WHERE r.EMPLOYEE_NUMBER = e.EMP_ID),0) AS FAMILY_NOT_COVERED,
            NVL((SELECT SUM(CASE WHEN PATIENT_TYPE = 20 THEN COVERED ELSE 0 END)
                 FROM FamilyClaims c WHERE c.EMPLOYEE_NUMBER = e.EMP_ID),0) * 0.75 AS COVID,
            NVL(fdd.DENTAL_FAMILY_DEDUCTION,0) AS DENTAL_FAMILY_DEDUCTION,
            NVL(fd.USAGE_FAMILY_DEDUCTION,0) AS USAGE_FAMILY_DEDUCTION,
            GREATEST(NVL(fd.USAGE_FAMILY_DEDUCTION,0), NVL(fdd.DENTAL_FAMILY_DEDUCTION,0)) AS TOTAL_FAMILY_DEDUCTION,
            NVL(pdd.DENTAL_PERSONAL_DEDUCTION,0) AS DENTAL_PERSONAL_DEDUCTION,
            GREATEST(NVL(fd.USAGE_FAMILY_DEDUCTION,0), NVL(fdd.DENTAL_FAMILY_DEDUCTION,0))
            + NVL(pdd.DENTAL_PERSONAL_DEDUCTION,0) AS TOTAL_DEDUCTION
        FROM Employees e
        JOIN LatestProject lp ON e.EMP_ID = lp.EMP_ID
        LEFT JOIN Limits l ON e.EMP_ID = l.EMP_ID
        LEFT JOIN Supports s ON e.EMP_ID = s.EMP_ID
        LEFT JOIN Discounts d ON e.EMP_ID = d.EMP_ID
        LEFT JOIN FamilyDeductionCalc fd ON e.EMP_ID = fd.EMP_ID
        LEFT JOIN FamilyDentalDeduction fdd ON e.EMP_ID = fdd.EMP_ID
        LEFT JOIN PersonalDentalDeduction pdd ON e.EMP_ID = pdd.EMP_ID
        WHERE NVL(
            GREATEST(NVL(fd.USAGE_FAMILY_DEDUCTION,0), NVL(fdd.DENTAL_FAMILY_DEDUCTION,0))
            + NVL(pdd.DENTAL_PERSONAL_DEDUCTION,0),
        0) > 0
        ORDER BY e.EMP_ID
    ) AS "data"
FROM DUAL;


    RETURN rc;
END;
/
