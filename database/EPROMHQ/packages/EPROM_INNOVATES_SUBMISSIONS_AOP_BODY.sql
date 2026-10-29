
  CREATE OR REPLACE EDITIONABLE PACKAGE BODY "EPROMHQ"."EPROM_INNOVATES_SUBMISSIONS_AOP" AS

  /* TODO enter package declarations (types, exceptions, methods etc) here */
FUNCTION GET_IDEA_SUBMISSIONS_JSON (
    p_selected_ids IN VARCHAR2
) RETURN CLOB
IS
    l_json CLOB;
BEGIN

    WITH submissions AS (
        SELECT
            submission_id,
            emp_number,
            emp_name,
            job_title,
            project_name,
            department_name,
            mobile_number,
            email_address,
            participation_type,
            team_members,
            idea_title,
            application_domain,
            application_domain_other,
            idea_description,
            problem_statement,
            expected_return,
            added_value,
            has_risks,
            risk_details,
            start_requirements,
            strategy_alignment,
            status,
            created_by,
            created_at
        FROM hq_elevated.sug_idea_submissions
        WHERE submission_id IN (
            SELECT TO_NUMBER(column_value)
            FROM TABLE(apex_string.split(p_selected_ids, ':'))
        )
    )
    SELECT
        JSON_ARRAYAGG(
            JSON_OBJECT(
                'filename' VALUE 'EPROM_Innovates_Submissions',
                'data' VALUE (
                    SELECT JSON_ARRAYAGG(
                        JSON_OBJECT(

                            'submissions' VALUE (
                                SELECT JSON_ARRAYAGG(
                                    JSON_OBJECT(

                                        'SUBMISSION_ID'            VALUE s.submission_id,
                                        'EMP_NUMBER'               VALUE s.emp_number,
                                        'EMP_NAME'                 VALUE s.emp_name,
                                        'JOB_TITLE'                VALUE s.job_title,
                                        'PROJECT_NAME'             VALUE s.project_name,
                                        'DEPARTMENT_NAME'          VALUE s.department_name,
                                        'MOBILE_NUMBER'            VALUE s.mobile_number,
                                        'EMAIL_ADDRESS'            VALUE s.email_address,
                                        'PARTICIPATION_TYPE'       VALUE s.participation_type,
                                        'TEAM_MEMBERS'             VALUE s.team_members,
                                        'IDEA_TITLE'               VALUE s.idea_title,
                                        'APPLICATION_DOMAIN'       VALUE s.application_domain,
                                        'APPLICATION_DOMAIN_OTHER' VALUE s.application_domain_other,
                                        'IDEA_DESCRIPTION'         VALUE s.idea_description,
                                        'PROBLEM_STATEMENT'        VALUE s.problem_statement,
                                        'EXPECTED_RETURN'          VALUE s.expected_return,
                                        'ADDED_VALUE'              VALUE s.added_value,
                                        'HAS_RISKS'                VALUE s.has_risks,
                                        'RISK_DETAILS'             VALUE s.risk_details,
                                        'START_REQUIREMENTS'       VALUE s.start_requirements,
                                        'STRATEGY_ALIGNMENT'       VALUE s.strategy_alignment,
                                        'STATUS'                   VALUE s.status,
                                        'CREATED_BY'               VALUE s.created_by,
                                        'CREATED_AT'               VALUE TO_CHAR(s.created_at,'DD-MM-YYYY HH24:MI:SS')

                                        RETURNING CLOB
                                    )
                                    ORDER BY s.submission_id
                                    RETURNING CLOB
                                )
                                FROM submissions s
                            ) FORMAT JSON

                            RETURNING CLOB
                        )
                        RETURNING CLOB
                    )
                    FROM dual
                ) FORMAT JSON

                RETURNING CLOB
            )
            RETURNING CLOB
        )
    INTO l_json
    FROM dual;

    RETURN l_json;

END GET_IDEA_SUBMISSIONS_JSON;


END EPROM_INNOVATES_SUBMISSIONS_AOP;
/
