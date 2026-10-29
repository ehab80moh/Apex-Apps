
  CREATE OR REPLACE FORCE EDITIONABLE VIEW "EPROMHQ"."PRF_EMP_CARDS_V" ("EMP_ID", "PERSON_ID", "EMPLOYEE_NAME", "DEPARTMENT", "SITE_CODE", "HAS_FRONT", "HAS_BACK", "ATTACHMENT_COUNT", "DATE_UPLOADED", "CARD_STATUS") AS
  select e.emp_number emp_id,e.person_id,e.emp_name employee_name,
       e.organization_name department,e.site_code,
       case when a.attach1 is not null then 1 else 0 end has_front,
       case when a.attach2 is not null then 1 else 0 end has_back,
       nvl(f.attachment_count,0) attachment_count,a.date_uploaded,
       case when a.attach1 is not null and a.attach2 is not null then 'COMPLETE'
            when nvl(f.attachment_count,0)>0 then 'INCOMPLETE' else 'NONE' end card_status
  from central.xxapex_hr_emp_data e
  left join hrf_person_attachments a on a.emp_id=e.emp_number and a.person_id=e.person_id
  left join (select emp_id,person_id,count(*) attachment_count
               from prf_emp_card_files_v group by emp_id,person_id) f
    on f.emp_id=e.emp_number and f.person_id=e.person_id;
