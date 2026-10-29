
  CREATE OR REPLACE FORCE EDITIONABLE VIEW "EPROMHQ"."APPROVER_FOR_EMPLOYEES" ("EMP_NUMBER", "LAST_APPROVER_59_FYA") AS
  SELECT
    e.emp_number,

    NVL(
        MAX(t.approver) KEEP (
            DENSE_RANK LAST
            ORDER BY
                t.approval_sequence,
                NVL(t.last_updated_date, DATE '1900-01-01'),
                t.cust_id
        ),
        'يرجى التكرم بمراجعة مسؤول الموارد البشرية المختص بموقعكم، وذلك لاستكمال إضافة المعتمد المطلوب'
    ) AS last_approver_59_fya

FROM central.xxapex_hr_emp_data e

LEFT JOIN central.apr_approval_results_cust_f t
    ON t.emp_number = e.emp_number
   AND t.request_type_id = 59
   AND t.approve_type = 'FYA'

GROUP BY e.emp_number;
