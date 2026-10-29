
  CREATE OR REPLACE FORCE EDITIONABLE VIEW "EPROMHQ"."TASK_FULL_DETAILS_V" ("TASK_ID", "APPLICATION_ID", "APPLICATION_NAME", "TASK_DEF_STATIC_ID", "SUBJECT", "INITIATOR", "ACTUAL_OWNER", "OUTCOME", "CREATED_BY", "CREATED_ON", "TASK_HISTORY_DATA", "TASK_PARAMETERS_DATA", "TASK_PARTICIPANTS_DATA") AS
  SELECT
    t.task_id,
    t.application_id,
    t.application_name,
    t.task_def_static_id,
    t.subject,
    t.initiator,
    t.actual_owner,
    t.outcome,
    t.created_by,
    t.created_on,
    (
        SELECT
            JSON_ARRAYAGG(JSON_OBJECT('event_type': event_type, 'event_creator': event_creator, 'outcome_code': outcome_code, 'event_timestamp': event_timestamp))
        FROM apex_task_history ath
        WHERE ath.task_id = t.task_id
    ) AS task_history_data,
    (
        SELECT
            JSON_ARRAYAGG(JSON_OBJECT('param_static_id': PARAM_STATIC_ID, 'param_value': param_value))
        FROM apex_task_parameters atp
        WHERE atp.task_id = t.task_id
    ) AS task_parameters_data,
    (
        SELECT
            JSON_ARRAYAGG(JSON_OBJECT('participant': participant, 'participant_type': participant_type))
        FROM apex_task_participants atpa
        WHERE atpa.task_id = t.task_id
        AND atpa.participant_type <> 'BUSINESS_ADMIN'
    ) AS task_participants_data
FROM
    apex_tasks t;
