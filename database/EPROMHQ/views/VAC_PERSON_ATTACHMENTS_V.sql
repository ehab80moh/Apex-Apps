
  CREATE OR REPLACE FORCE EDITIONABLE VIEW "EPROMHQ"."VAC_PERSON_ATTACHMENTS_V" ("ATTACH_ID", "EMPLOYEE_NUMBER", "EMPLOYEE_NAME", "EMP_PERSON_ID", "RELATIVE_PERSON_ID", "RELATIVE_TYPE", "RELATIVE_NAME", "ATTACH1", "ATTACH2", "ATTACH3", "ATTACH4") AS
  SELECT
  at.ATTACH_ID,
  e.EMP_NUMBER             AS employee_number,
  e.EMP_NAME               AS employee_name,
  e.PERSON_ID              AS emp_person_id,
  e.PERSON_ID              AS relative_person_id,  -- أو NULL لو تحب
  CASE
    WHEN LOWER(APEX_UTIL.GET_SESSION_LANG) = 'en-us' THEN 'Employee'
    ELSE 'الموظف'
  END AS relative_type,
  e.EMP_NAME AS relative_name,

  NVL2(at.ATTACH1, lightbox_image('/attach/'||at.ATTACH1, 'Attachment 1',
      CASE WHEN LOWER(APEX_UTIL.GET_SESSION_LANG) = 'en-us' THEN 'View' ELSE 'عرض' END),
       '-') AS attach1,
  NVL2(at.ATTACH2, lightbox_image('/attach/'||at.ATTACH2, 'Attachment 2',
      CASE WHEN LOWER(APEX_UTIL.GET_SESSION_LANG) = 'en-us' THEN 'View' ELSE 'عرض' END),
       '-') AS attach2,
  NVL2(at.ATTACH3, lightbox_image('/attach/'||at.ATTACH3, 'Attachment 3',
      CASE WHEN LOWER(APEX_UTIL.GET_SESSION_LANG) = 'en-us' THEN 'View' ELSE 'عرض' END),
       '-') AS attach3,
  NVL2(at.ATTACH4, lightbox_image('/attach/'||at.ATTACH4, 'Attachment 4',
      CASE WHEN LOWER(APEX_UTIL.GET_SESSION_LANG) = 'en-us' THEN 'View' ELSE 'عرض' END),
       '-') AS attach4

FROM CENTRAL.xxapex_hr_emp_data e
LEFT JOIN HRF_PERSON_ATTACHMENTS at
  ON at.PERSON_ID = e.PERSON_ID

UNION ALL

-- مرفقات العائلة كما في الكود الأصلي
SELECT
  at.ATTACH_ID,
  r.employee_number,
  r.employee_name,
  r.emp_person_id,
  r.relative_person_id,
  r.relative_type,
  r.relative_name,
  NVL2(at.ATTACH1, lightbox_image('/attach/'||at.ATTACH1, 'Attachment 1',
      CASE WHEN LOWER(APEX_UTIL.GET_SESSION_LANG) = 'en-us' THEN 'View' ELSE 'عرض' END),
       '-') AS attach1,
  NVL2(at.ATTACH2, lightbox_image('/attach/'||at.ATTACH2, 'Attachment 2',
      CASE WHEN LOWER(APEX_UTIL.GET_SESSION_LANG) = 'en-us' THEN 'View' ELSE 'عرض' END),
       '-') AS attach2,
  NVL2(at.ATTACH3, lightbox_image('/attach/'||at.ATTACH3, 'Attachment 3',
      CASE WHEN LOWER(APEX_UTIL.GET_SESSION_LANG) = 'en-us' THEN 'View' ELSE 'عرض' END),
       '-') AS attach3,
  NVL2(at.ATTACH4, lightbox_image('/attach/'||at.ATTACH4, 'Attachment 4',
      CASE WHEN LOWER(APEX_UTIL.GET_SESSION_LANG) = 'en-us' THEN 'View' ELSE 'عرض' END),
       '-') AS attach4
FROM CENTRAL.xxapex_hr_emp_relatives r
LEFT JOIN HRF_PERSON_ATTACHMENTS at
  ON at.PERSON_ID = r.relative_person_id;
