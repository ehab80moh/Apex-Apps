
  CREATE OR REPLACE FORCE EDITIONABLE VIEW "EPROMHQ"."PRF_EMP_CARD_FILES_V" ("EMP_ID", "PERSON_ID", "ATTACH_ID", "SLOT_NO", "FILE_NAME") AS
  select a.emp_id,a.person_id,min(a.attach_id) attach_id,min(a.slot_no) slot_no,a.file_name
  from (
    select attach_id,emp_id,person_id,slot_no,file_name
      from hrf_person_attachments
      unpivot (file_name for slot_no in (attach1 as 1,attach2 as 2,attach3 as 3,attach4 as 4))
  ) a
 where exists (select 1 from central.xxapex_hr_emp_data e
                where e.emp_number=a.emp_id and e.person_id=a.person_id)
 group by a.emp_id,a.person_id,a.file_name;
