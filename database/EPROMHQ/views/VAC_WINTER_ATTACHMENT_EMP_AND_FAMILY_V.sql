
  CREATE OR REPLACE FORCE EDITIONABLE VIEW "EPROMHQ"."VAC_WINTER_ATTACHMENT_EMP_AND_FAMILY_V" ("ATTACH_ID", "EMPLOYEE_NUMBER", "EMPLOYEE_NAME", "EMP_PERSON_ID", "RELATIVE_PERSON_ID", "RELATIVE_TYPE", "RELATIVE_NAME", "ATTACH1", "ATTACH2", "ATTACH3", "ATTACH4", "PERSON_TYPE", "FAMILY_MEMBER_ID", "FAMILY_RELATION", "IN_WINTER_LIST", "BIRTH_DATE", "AGE") AS
  WITH at_one AS (
  SELECT *
  FROM (
    SELECT a.*, ROW_NUMBER() OVER (PARTITION BY a.person_id ORDER BY a.attach_id DESC) rn
    FROM Epromhq.HRF_PERSON_ATTACHMENTS a
  )
  WHERE rn = 1
),
-- الحصول على بيانات العائلات من VAC_WINTER_2026_FAMILY_V
winter_families AS (
  SELECT DISTINCT
    f.EMP_NO,
    f.FULL_NAME,
    f.RELATION_DESC,
    f.BIRTH_DATE,
    f.AGE_YEARS_25_1_2025 AS AGE,
    ROW_NUMBER() OVER (ORDER BY f.M) AS family_member_id
  FROM VAC_WINTER_2026_FAMILY_V f
  WHERE f.EMP_NO IS NOT NULL OR f.FULL_NAME IS NOT NULL
),
-- بيانات الموظفين الأساسية
employee_base AS (
  SELECT
    at.ATTACH_ID,
    e.EMP_NUMBER as employee_number,
    e.EMP_NAME as employee_name,
    e.PERSON_ID AS emp_person_id,
    e.PERSON_ID AS relative_person_id,  -- الموظف نفسه
    CASE WHEN LOWER(APEX_UTIL.GET_SESSION_LANG) = 'ar-ae' THEN 'الموظف' ELSE 'Employee' END AS relative_type,
    e.EMP_NAME AS relative_name,
    NVL2(at.ATTACH1, '<a href="/attach/' || at.ATTACH1 || '" data-lightbox="image" data-title="Attachment 1">' ||
      CASE WHEN LOWER(APEX_UTIL.GET_SESSION_LANG) = 'ar-ae' THEN 'عرض' ELSE 'View' END || '</a>', '-') AS ATTACH1,
    NVL2(at.ATTACH2, '<a href="/attach/' || at.ATTACH2 || '" data-lightbox="image" data-title="Attachment 2">' ||
      CASE WHEN LOWER(APEX_UTIL.GET_SESSION_LANG) = 'ar-ae' THEN 'عرض' ELSE 'View' END || '</a>', '-') AS ATTACH2,
    NVL2(at.ATTACH3, '<a href="/attach/' || at.ATTACH3 || '" data-lightbox="image" data-title="Attachment 3">' ||
      CASE WHEN LOWER(APEX_UTIL.GET_SESSION_LANG) = 'ar-ae' THEN 'عرض' ELSE 'View' END || '</a>', '-') AS ATTACH3,
    NVL2(at.ATTACH4, '<a href="/attach/' || at.ATTACH4 || '" data-lightbox="image" data-title="Attachment 4">' ||
      CASE WHEN LOWER(APEX_UTIL.GET_SESSION_LANG) = 'ar-ae' THEN 'عرض' ELSE 'View' END || '</a>', '-') AS ATTACH4,
    1 as person_type,
    -- بيانات العائلة للموظف
    wf.family_member_id,
    wf.RELATION_DESC AS family_relation,
    CASE WHEN wf.EMP_NO IS NOT NULL THEN 'Y' ELSE 'N' END AS in_winter_list,
    wf.BIRTH_DATE,
    wf.AGE
  FROM CENTRAL.XXAPEX_HR_EMP_DATA e
  LEFT JOIN at_one at ON at.PERSON_ID = e.PERSON_ID
  LEFT JOIN winter_families wf ON wf.EMP_NO = e.EMP_NUMBER AND wf.RELATION_DESC = 'العامل'
  WHERE e.EMP_NUMBER in (select emp_no from VAC_WINTER_2026_FAMILY_V)
    AND at.ATTACH_ID IS NOT NULL
),
-- بيانات الأقارب
relative_base AS (
  SELECT
    at.ATTACH_ID,
    r.employee_number,
    e.EMP_NAME as employee_name,
    r.emp_person_id,
    r.relative_person_id,
    CASE
      WHEN LOWER(APEX_UTIL.GET_SESSION_LANG) = 'ar-ae' THEN r.relative_type
      ELSE CASE r.relative_type
        WHEN 'الزوج' THEN 'Spouse'
        WHEN 'الوالد' THEN 'Father'
        WHEN 'الوالدة' THEN 'Mother'
        WHEN 'ابن' THEN 'Son'
        ELSE r.relative_type
      END
    END AS relative_type,
    r.relative_name,
    NVL2(at.ATTACH1, '<a href="/attach/' || at.ATTACH1 || '" data-lightbox="image" data-title="Attachment 1">' ||
      CASE WHEN LOWER(APEX_UTIL.GET_SESSION_LANG) = 'ar-ae' THEN 'عرض' ELSE 'View' END || '</a>', '-') AS ATTACH1,
    NVL2(at.ATTACH2, '<a href="/attach/' || at.ATTACH2 || '" data-lightbox="image" data-title="Attachment 2">' ||
      CASE WHEN LOWER(APEX_UTIL.GET_SESSION_LANG) = 'ar-ae' THEN 'عرض' ELSE 'View' END || '</a>', '-') AS ATTACH2,
    NVL2(at.ATTACH3, '<a href="/attach/' || at.ATTACH3 || '" data-lightbox="image" data-title="Attachment 3">' ||
      CASE WHEN LOWER(APEX_UTIL.GET_SESSION_LANG) = 'ar-ae' THEN 'عرض' ELSE 'View' END || '</a>', '-') AS ATTACH3,
    NVL2(at.ATTACH4, '<a href="/attach/' || at.ATTACH4 || '" data-lightbox="image" data-title="Attachment 4">' ||
      CASE WHEN LOWER(APEX_UTIL.GET_SESSION_LANG) = 'ar-ae' THEN 'عرض' ELSE 'View' END || '</a>', '-') AS ATTACH4,
    2 as person_type,
    -- بيانات العائلة للقريب
    wf.family_member_id,
    wf.RELATION_DESC AS family_relation,
    CASE WHEN wf.FULL_NAME IS NOT NULL THEN 'Y' ELSE 'N' END AS in_winter_list,
    wf.BIRTH_DATE,
    wf.AGE
  FROM CENTRAL.xxapex_hr_emp_relatives r
  JOIN CENTRAL.XXAPEX_HR_EMP_DATA e ON e.EMP_NUMBER = r.employee_number
  LEFT JOIN at_one at ON at.person_id = r.relative_person_id
  LEFT JOIN winter_families wf ON wf.FULL_NAME = r.relative_name
  WHERE r.employee_number in (select emp_no from VAC_WINTER_2026_FAMILY_V)
    AND at.ATTACH_ID IS NOT NULL
)
-- دمج البيانات
SELECT
    ATTACH_ID,
    employee_number,
    employee_name,
    emp_person_id,
    relative_person_id,
    relative_type,
    relative_name,
    ATTACH1,
    ATTACH2,
    ATTACH3,
    ATTACH4,
    person_type,
    family_member_id,
    family_relation,
    in_winter_list,
    BIRTH_DATE,
    AGE
FROM employee_base

UNION ALL

SELECT
    ATTACH_ID,
    employee_number,
    employee_name,
    emp_person_id,
    relative_person_id,
    relative_type,
    relative_name,
    ATTACH1,
    ATTACH2,
    ATTACH3,
    ATTACH4,
    person_type,
    family_member_id,
    family_relation,
    in_winter_list,
    BIRTH_DATE,
    AGE
FROM relative_base
where IN_WINTER_LIST ='Y'
ORDER BY
    employee_number,
    person_type,
    family_relation,
    relative_name;
