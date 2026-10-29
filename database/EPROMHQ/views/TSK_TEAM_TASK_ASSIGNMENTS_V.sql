
  CREATE OR REPLACE FORCE EDITIONABLE VIEW "EPROMHQ"."TSK_TEAM_TASK_ASSIGNMENTS_V" ("TEAM_ID", "TEAM_NAME", "TEAM_LEADERS", "TEAM_MEMBERS", "PROJECT_ID", "PROJECT_NAME", "PROJECT_DESC", "START_DATE", "END_DATE", "STATUS", "TASK_ID", "TASK_NAME", "TASK_START_DATE", "TASK_DUE_DATE", "TASK_END_DATE", "TASK_STATUS", "TA_ASSIGMENT_ID", "TA_ASSIGNMENT_NAME", "TA_EMPLOYEE_ID", "TA_ASSIGN_DATE", "TA_END_DATE", "TA_STATUS", "PRIORITY") AS
  select t."TEAM_ID",t."TEAM_NAME",t."TEAM_LEADERS",t."TEAM_MEMBERS",
  p.project_id,p.project_name,p.project_desc,p.start_date,p.end_date,p.status
  ,ta.task_id,ta.task_name,ta.task_start_date,ta.task_due_date,ta.task_end_date,ta.task_status,
  tas.ta_assigment_id,tas.ta_assignment_name,tas.ta_employee_id,tas.ta_assign_date,tas.ta_end_date,tas.ta_status,tas.priority
  from tsk_teams t
  JOIN tsk_projects p on t.team_id = p.team_id
  join tsk_tasks ta on ta.project_id = p.project_id
  join tsk_task_assignment tas on tas.task_id = ta.task_id;
