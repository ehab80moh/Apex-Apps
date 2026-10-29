
  CREATE OR REPLACE EDITIONABLE PACKAGE BODY "HQ_ELEVATED"."GEN_WF_LOG_PKG" AS

   ----------------------------------------------------------------------------------------------------------------------------------
   -- Procedure: CAPTURE_WORKFLOW_LOG
   -- Purpose: Merges complete workflow instance data into GEN_WF_WORKFLOW_LOG
   ----------------------------------------------------------------------------------------------------------------------------------
   PROCEDURE CAPTURE_WORKFLOW_LOG(P_WORKFLOW_ID IN NUMBER) AS
   BEGIN
      MERGE INTO GEN_WF_WORKFLOW_LOG TARGET
      USING (SELECT *
               FROM (SELECT WF.*
                           ,(SELECT JSON_ARRAYAGG(JSON_OBJECT('name' VALUE NAME,
                                                              'typeCode' VALUE TYPE_CODE,
                                                              'startTime' VALUE START_TIME,
                                                              'endTime' VALUE END_TIME,
                                                              'errorMessage' VALUE ERROR_MESSAGE,
                                                              'retryCount' VALUE RETRY_COUNT,
                                                              'activityId' VALUE ACTIVITY_ID) ORDER BY ACTIVITY_ID
                                                 RETURNING CLOB)
                               FROM APEX_WORKFLOW_ACTIVITIES WFA
                              WHERE WFA.WORKFLOW_ID = WF.WORKFLOW_ID) AS WORKFLOW_ACTIVITIES
                           ,(SELECT JSON_ARRAYAGG(JSON_OBJECT('participantTypeCode' VALUE PARTICIPANT_TYPE_CODE,
                                                              'participant' VALUE PARTICIPANT) ORDER BY
                                                 PARTICIPANT_TYPE_CODE RETURNING CLOB)
                               FROM APEX_WORKFLOW_PARTICIPANTS WFPR
                              WHERE WFPR.WORKFLOW_ID = WF.WORKFLOW_ID) AS WORKFLOW_PARTICIPANTS
                           ,(SELECT JSON_ARRAYAGG(JSON_OBJECT('staticId' VALUE STATIC_ID,
                                                              'displayValue' VALUE DISPLAY_VALUE,
                                                              'direction' VALUE DIRECTION,
                                                              'dataTypeCode' VALUE DATA_TYPE_CODE) ORDER BY VARIABLE_ID
                                                 RETURNING CLOB)
                               FROM APEX_WORKFLOW_VARIABLES WFV
                              WHERE WFV.WORKFLOW_ID = WF.WORKFLOW_ID) AS WORKFLOW_VARIABLES
                           ,(SELECT JSON_ARRAYAGG(JSON_OBJECT('stateCode' VALUE STATE_CODE,
                                                              'actionCode' VALUE ACTION_CODE,
                                                              'displayMsg' VALUE DISPLAY_MSG,
                                                              'createdOn' VALUE CREATED_ON,
                                                              'createdBy' VALUE CREATED_BY,
                                                              'lastUpdatedBy' VALUE LAST_UPDATED_BY) RETURNING CLOB)
                               FROM APEX_WORKFLOW_AUDIT WFAU
                              WHERE WFAU.WORKFLOW_ID = WF.WORKFLOW_ID) AS WORKFLOW_AUDIT
                       FROM APEX_WORKFLOWS WF)
              WHERE WORKFLOW_ID = P_WORKFLOW_ID) SOURCE
      ON (TARGET.WORKFLOW_ID = SOURCE.WORKFLOW_ID)
      WHEN MATCHED THEN
         UPDATE
            SET TARGET.WORKSPACE_ID           = SOURCE.WORKSPACE_ID
               ,TARGET.WORKSPACE              = SOURCE.WORKSPACE
               ,TARGET.WORKSPACE_DISPLAY_NAME = SOURCE.WORKSPACE_DISPLAY_NAME
               ,TARGET.APPLICATION_ID         = SOURCE.APPLICATION_ID
               ,TARGET.APPLICATION_NAME       = SOURCE.APPLICATION_NAME
               ,TARGET.WORKFLOW_DEF_ID        = SOURCE.WORKFLOW_DEF_ID
               ,TARGET.WORKFLOW_DEF_NAME      = SOURCE.WORKFLOW_DEF_NAME
               ,TARGET.WORKFLOW_DEF_STATIC_ID = SOURCE.WORKFLOW_DEF_STATIC_ID
               ,TARGET.TITLE                  = SOURCE.TITLE
               ,TARGET.WORKFLOW_VERSION_ID    = SOURCE.WORKFLOW_VERSION_ID
               ,TARGET.WORKFLOW_VERSION       = SOURCE.WORKFLOW_VERSION
               ,TARGET.WORKFLOW_VERSION_STATE = SOURCE.WORKFLOW_VERSION_STATE
               ,TARGET.DETAIL_PK              = SOURCE.DETAIL_PK
               ,TARGET.INITIATOR              = SOURCE.INITIATOR
               ,TARGET.STATE_CODE             = SOURCE.STATE_CODE
               ,TARGET.STATE                  = SOURCE.STATE
               ,TARGET.START_TIME             = SOURCE.START_TIME
               ,TARGET.END_TIME               = SOURCE.END_TIME
               ,TARGET.IS_DEV_MODE            = SOURCE.IS_DEV_MODE
               ,TARGET.LAST_UPDATED_BY        = SOURCE.LAST_UPDATED_BY
               ,TARGET.LAST_UPDATED_ON        = SOURCE.LAST_UPDATED_ON
               ,TARGET.WORKFLOW_ACTIVITIES    = SOURCE.WORKFLOW_ACTIVITIES
               ,TARGET.WORKFLOW_PARTICIPANTS  = SOURCE.WORKFLOW_PARTICIPANTS
               ,TARGET.WORKFLOW_VARIABLES     = SOURCE.WORKFLOW_VARIABLES
               ,TARGET.WORKFLOW_AUDIT         = SOURCE.WORKFLOW_AUDIT
               ,TARGET.PARENT_WORKFLOW_ID     = SOURCE.PARENT_WORKFLOW_ID
               ,TARGET.PARENT_ACTIVITY_ID     = SOURCE.PARENT_ACTIVITY_ID
      WHEN NOT MATCHED THEN
         INSERT
            (WORKFLOW_ID, WORKSPACE_ID, WORKSPACE, WORKSPACE_DISPLAY_NAME, APPLICATION_ID, APPLICATION_NAME, WORKFLOW_DEF_ID, WORKFLOW_DEF_NAME, WORKFLOW_DEF_STATIC_ID, TITLE, WORKFLOW_VERSION_ID, WORKFLOW_VERSION, WORKFLOW_VERSION_STATE, DETAIL_PK, INITIATOR, STATE_CODE, STATE, START_TIME, END_TIME, IS_DEV_MODE, LAST_UPDATED_BY, LAST_UPDATED_ON, WORKFLOW_ACTIVITIES, WORKFLOW_PARTICIPANTS, WORKFLOW_VARIABLES, WORKFLOW_AUDIT, PARENT_WORKFLOW_ID, PARENT_ACTIVITY_ID)
         VALUES
            (SOURCE.WORKFLOW_ID, SOURCE.WORKSPACE_ID, SOURCE.WORKSPACE, SOURCE.WORKSPACE_DISPLAY_NAME, SOURCE.APPLICATION_ID, SOURCE.APPLICATION_NAME, SOURCE.WORKFLOW_DEF_ID, SOURCE.WORKFLOW_DEF_NAME, SOURCE.WORKFLOW_DEF_STATIC_ID, SOURCE.TITLE, SOURCE.WORKFLOW_VERSION_ID, SOURCE.WORKFLOW_VERSION, SOURCE.WORKFLOW_VERSION_STATE, SOURCE.DETAIL_PK, SOURCE.INITIATOR, SOURCE.STATE_CODE, SOURCE.STATE, SOURCE.START_TIME, SOURCE.END_TIME, SOURCE.IS_DEV_MODE, SOURCE.LAST_UPDATED_BY, SOURCE.LAST_UPDATED_ON, SOURCE.WORKFLOW_ACTIVITIES, SOURCE.WORKFLOW_PARTICIPANTS, SOURCE.WORKFLOW_VARIABLES, SOURCE.WORKFLOW_AUDIT, SOURCE.PARENT_WORKFLOW_ID, SOURCE.PARENT_ACTIVITY_ID);

   EXCEPTION
      WHEN OTHERS THEN
         LOG_ERROR(
            P_CALLING_PROC  => 'GEN_WF_LOG_PKG.CAPTURE_WORKFLOW_LOG',
            P_ERROR_CODE    => TO_CHAR(SQLCODE),
            P_ERROR_MESSAGE => SQLERRM,
            P_ERROR_STACK   => DBMS_UTILITY.FORMAT_ERROR_BACKTRACE
         );
         RAISE;
   END CAPTURE_WORKFLOW_LOG;

   ----------------------------------------------------------------------------------------------------------------------------------
   -- Procedure: CAPTURE_TASK_LOG
   -- Purpose: Merges task log data into GEN_WF_TASK_LOG
   ----------------------------------------------------------------------------------------------------------------------------------
   PROCEDURE CAPTURE_TASK_LOG(P_TASK_ID IN NUMBER) AS
   BEGIN
      MERGE INTO GEN_WF_TASK_LOG TARGET
      USING (SELECT TASK_ID
                   ,WORKSPACE_ID
                   ,WORKFLOW_ID
                   ,WORKSPACE
                   ,WORKSPACE_DISPLAY_NAME
                   ,APPLICATION_ID
                   ,APPLICATION_NAME
                   ,WORKING_COPY_NAME
                   ,TASK_DEF_ID
                   ,TASK_DEF_NAME
                   ,TASK_DEF_STATIC_ID
                   ,PREVIOUS_TASK_ID
                   ,SUBJECT
                   ,TASK_TYPE_CODE
                   ,TASK_TYPE
                   ,DUE_ON
                   ,PRIORITY
                   ,PRIORITY_LEVEL
                   ,DETAIL_PK
                   ,INITIATOR
                   ,INITIATOR_CAN_COMPLETE
                   ,ACTUAL_OWNER
                   ,PREVIOUS_OWNER
                   ,STATE_CODE
                   ,STATE
                   ,RENEWAL_COUNT
                   ,OUTCOME_CODE
                   ,OUTCOME
                   ,CREATED_BY
                   ,CREATED_ON
                   ,LAST_UPDATED_BY
                   ,LAST_UPDATED_ON
                   ,TASK_HISTORY_DATA
                   ,TASK_PARAMETERS_DATA
                   ,TASK_PARTICIPANTS_DATA
               FROM (SELECT T.*
                           ,(SELECT JSON_ARRAYAGG(JSON_OBJECT(KEY 'event_type' VALUE EVENT_TYPE,
                                                              KEY 'event_creator' VALUE EVENT_CREATOR,
                                                              KEY 'outcome_code' VALUE OUTCOME_CODE,
                                                              KEY 'event_timestamp' VALUE EVENT_TIMESTAMP) RETURNING CLOB)
                               FROM APEX_TASK_HISTORY ATH
                              WHERE ATH.TASK_ID = T.TASK_ID) AS TASK_HISTORY_DATA
                           ,(SELECT JSON_ARRAYAGG(JSON_OBJECT(KEY 'param_static_id' VALUE PARAM_STATIC_ID,
                                                              KEY 'param_value' VALUE PARAM_VALUE) RETURNING CLOB)
                               FROM APEX_TASK_PARAMETERS ATP
                              WHERE ATP.TASK_ID = T.TASK_ID) AS TASK_PARAMETERS_DATA
                           ,(SELECT JSON_ARRAYAGG(JSON_OBJECT(KEY 'participant' VALUE PARTICIPANT,
                                                              KEY 'participant_type' VALUE PARTICIPANT_TYPE) RETURNING CLOB)
                               FROM APEX_TASK_PARTICIPANTS ATPA
                              WHERE ATPA.TASK_ID = T.TASK_ID
                                AND ATPA.PARTICIPANT_TYPE <> 'BUSINESS_ADMIN') AS TASK_PARTICIPANTS_DATA
                       FROM APEX_TASKS T)
              WHERE TASK_ID = P_TASK_ID) SOURCE
      ON (TARGET.TASK_ID = SOURCE.TASK_ID)
      WHEN MATCHED THEN
         UPDATE
            SET TARGET.WORKSPACE_ID           = SOURCE.WORKSPACE_ID
               ,TARGET.WORKFLOW_ID            = SOURCE.WORKFLOW_ID
               ,TARGET.WORKSPACE              = SOURCE.WORKSPACE
               ,TARGET.WORKSPACE_DISPLAY_NAME = SOURCE.WORKSPACE_DISPLAY_NAME
               ,TARGET.APPLICATION_ID         = SOURCE.APPLICATION_ID
               ,TARGET.APPLICATION_NAME       = SOURCE.APPLICATION_NAME
               ,TARGET.WORKING_COPY_NAME      = SOURCE.WORKING_COPY_NAME
               ,TARGET.TASK_DEF_ID            = SOURCE.TASK_DEF_ID
               ,TARGET.TASK_DEF_NAME          = SOURCE.TASK_DEF_NAME
               ,TARGET.TASK_DEF_STATIC_ID     = SOURCE.TASK_DEF_STATIC_ID
               ,TARGET.PREVIOUS_TASK_ID       = SOURCE.PREVIOUS_TASK_ID
               ,TARGET.SUBJECT                = SOURCE.SUBJECT
               ,TARGET.TASK_TYPE_CODE         = SOURCE.TASK_TYPE_CODE
               ,TARGET.TASK_TYPE              = SOURCE.TASK_TYPE
               ,TARGET.DUE_ON                 = SOURCE.DUE_ON
               ,TARGET.PRIORITY               = SOURCE.PRIORITY
               ,TARGET.PRIORITY_LEVEL         = SOURCE.PRIORITY_LEVEL
               ,TARGET.DETAIL_PK              = SOURCE.DETAIL_PK
               ,TARGET.INITIATOR              = SOURCE.INITIATOR
               ,TARGET.INITIATOR_CAN_COMPLETE = SOURCE.INITIATOR_CAN_COMPLETE
               ,TARGET.ACTUAL_OWNER           = SOURCE.ACTUAL_OWNER
               ,TARGET.PREVIOUS_OWNER         = SOURCE.PREVIOUS_OWNER
               ,TARGET.STATE_CODE             = SOURCE.STATE_CODE
               ,TARGET.STATE                  = SOURCE.STATE
               ,TARGET.RENEWAL_COUNT          = SOURCE.RENEWAL_COUNT
               ,TARGET.OUTCOME_CODE           = SOURCE.OUTCOME_CODE
               ,TARGET.OUTCOME                = SOURCE.OUTCOME
               ,TARGET.CREATED_BY             = SOURCE.CREATED_BY
               ,TARGET.CREATED_ON             = SOURCE.CREATED_ON
               ,TARGET.LAST_UPDATED_BY        = SOURCE.LAST_UPDATED_BY
               ,TARGET.LAST_UPDATED_ON        = SOURCE.LAST_UPDATED_ON
               ,TARGET.TASK_HISTORY_DATA      = SOURCE.TASK_HISTORY_DATA
               ,TARGET.TASK_PARAMETERS_DATA   = SOURCE.TASK_PARAMETERS_DATA
               ,TARGET.TASK_PARTICIPANTS_DATA = SOURCE.TASK_PARTICIPANTS_DATA
      WHEN NOT MATCHED THEN
         INSERT
            (TASK_ID, WORKSPACE_ID, WORKFLOW_ID, WORKSPACE, WORKSPACE_DISPLAY_NAME, APPLICATION_ID, APPLICATION_NAME, WORKING_COPY_NAME, TASK_DEF_ID, TASK_DEF_NAME, TASK_DEF_STATIC_ID, PREVIOUS_TASK_ID, SUBJECT, TASK_TYPE_CODE, TASK_TYPE, DUE_ON, PRIORITY, PRIORITY_LEVEL, DETAIL_PK, INITIATOR, INITIATOR_CAN_COMPLETE, ACTUAL_OWNER, PREVIOUS_OWNER, STATE_CODE, STATE, RENEWAL_COUNT, OUTCOME_CODE, OUTCOME, CREATED_BY, CREATED_ON, LAST_UPDATED_BY, LAST_UPDATED_ON, TASK_HISTORY_DATA, TASK_PARAMETERS_DATA, TASK_PARTICIPANTS_DATA)
         VALUES
            (SOURCE.TASK_ID, SOURCE.WORKSPACE_ID, SOURCE.WORKFLOW_ID, SOURCE.WORKSPACE, SOURCE.WORKSPACE_DISPLAY_NAME, SOURCE.APPLICATION_ID, SOURCE.APPLICATION_NAME, SOURCE.WORKING_COPY_NAME, SOURCE.TASK_DEF_ID, SOURCE.TASK_DEF_NAME, SOURCE.TASK_DEF_STATIC_ID, SOURCE.PREVIOUS_TASK_ID, SOURCE.SUBJECT, SOURCE.TASK_TYPE_CODE, SOURCE.TASK_TYPE, SOURCE.DUE_ON, SOURCE.PRIORITY, SOURCE.PRIORITY_LEVEL, SOURCE.DETAIL_PK, SOURCE.INITIATOR, SOURCE.INITIATOR_CAN_COMPLETE, SOURCE.ACTUAL_OWNER, SOURCE.PREVIOUS_OWNER, SOURCE.STATE_CODE, SOURCE.STATE, SOURCE.RENEWAL_COUNT, SOURCE.OUTCOME_CODE, SOURCE.OUTCOME, SOURCE.CREATED_BY, SOURCE.CREATED_ON, SOURCE.LAST_UPDATED_BY, SOURCE.LAST_UPDATED_ON, SOURCE.TASK_HISTORY_DATA, SOURCE.TASK_PARAMETERS_DATA, SOURCE.TASK_PARTICIPANTS_DATA);

   EXCEPTION
      WHEN OTHERS THEN
         LOG_ERROR(
            P_CALLING_PROC  => 'GEN_WF_LOG_PKG.CAPTURE_TASK_LOG',
            P_ERROR_CODE    => TO_CHAR(SQLCODE),
            P_ERROR_MESSAGE => SQLERRM,
            P_ERROR_STACK   => DBMS_UTILITY.FORMAT_ERROR_BACKTRACE
         );
         RAISE;
   END CAPTURE_TASK_LOG;

   ----------------------------------------------------------------------------------------------------------------------------------
   -- Procedure: CAPTURE_ALL_WF_TASKS
   -- Purpose: Captures all task logs associated with a workflow instance.
   ----------------------------------------------------------------------------------------------------------------------------------
   PROCEDURE CAPTURE_ALL_WF_TASKS(P_WORKFLOW_ID IN NUMBER) AS
   BEGIN
      FOR C IN (SELECT TASK_ID FROM APEX_TASKS WHERE WORKFLOW_ID = P_WORKFLOW_ID) LOOP
         CAPTURE_TASK_LOG(P_TASK_ID => C.TASK_ID);
      END LOOP;
   EXCEPTION
      WHEN OTHERS THEN
         LOG_ERROR(
            P_CALLING_PROC  => 'GEN_WF_LOG_PKG.CAPTURE_ALL_WF_TASKS',
            P_ERROR_CODE    => TO_CHAR(SQLCODE),
            P_ERROR_MESSAGE => SQLERRM,
            P_ERROR_STACK   => DBMS_UTILITY.FORMAT_ERROR_BACKTRACE
         );
         RAISE;
   END CAPTURE_ALL_WF_TASKS;

   ----------------------------------------------------------------------------------------------------------------------------------
   -- Procedure: LOG_ERROR
   -- Purpose: Autonomous transaction error logger
   ----------------------------------------------------------------------------------------------------------------------------------
   PROCEDURE LOG_ERROR (
      P_CALLING_PROC  IN VARCHAR2,
      P_ERROR_CODE    IN VARCHAR2,
      P_ERROR_MESSAGE IN VARCHAR2,
      P_ERROR_STACK   IN CLOB DEFAULT NULL
   ) IS
      PRAGMA AUTONOMOUS_TRANSACTION;
   BEGIN
      INSERT INTO GEN_WF_ERRORS (
         ERROR_DATE, ERROR_CODE, ERROR_MESSAGE, ERROR_STACK, CALLING_PROC, USER_NAME
      ) VALUES (
         SYSTIMESTAMP, P_ERROR_CODE, P_ERROR_MESSAGE, P_ERROR_STACK, P_CALLING_PROC, NVL(V('APP_USER'), USER)
      );
      COMMIT;
   EXCEPTION
      WHEN OTHERS THEN
         ROLLBACK;
   END LOG_ERROR;

   ----------------------------------------------------------------------------------------------------------------------------------
   -- Function: GET_WORKFLOW_VARIABLE
   -- Purpose: Extracts a specific variable's display value from logged WORKFLOW_VARIABLES JSON array
   ----------------------------------------------------------------------------------------------------------------------------------
   FUNCTION GET_WORKFLOW_VARIABLE (
      P_WORKFLOW_ID   IN NUMBER,
      P_VAR_STATIC_ID IN VARCHAR2
   ) RETURN VARCHAR2 IS
      V_RES VARCHAR2(4000);
   BEGIN
      SELECT JSON_VALUE(WORKFLOW_VARIABLES, '$[*] ? (@.staticId == $var).displayValue' PASSING P_VAR_STATIC_ID AS "var")
        INTO V_RES
        FROM GEN_WF_WORKFLOW_LOG
       WHERE WORKFLOW_ID = P_WORKFLOW_ID;
      RETURN V_RES;
   EXCEPTION
      WHEN OTHERS THEN
         RETURN NULL;
   END GET_WORKFLOW_VARIABLE;

   ----------------------------------------------------------------------------------------------------------------------------------
   -- Function: GET_TASK_PARAMETER
   -- Purpose: Extracts a specific parameter value from logged TASK_PARAMETERS_DATA JSON array
   ----------------------------------------------------------------------------------------------------------------------------------
   FUNCTION GET_TASK_PARAMETER (
      P_TASK_ID         IN NUMBER,
      P_PARAM_STATIC_ID IN VARCHAR2
   ) RETURN VARCHAR2 IS
      V_RES VARCHAR2(4000);
   BEGIN
      SELECT JSON_VALUE(TASK_PARAMETERS_DATA, '$[*] ? (@.param_static_id == $param).param_value' PASSING P_PARAM_STATIC_ID AS "param")
        INTO V_RES
        FROM GEN_WF_TASK_LOG
       WHERE TASK_ID = P_TASK_ID;
      RETURN V_RES;
   EXCEPTION
      WHEN OTHERS THEN
         RETURN NULL;
   END GET_TASK_PARAMETER;

   ----------------------------------------------------------------------------------------------------------------------------------
   -- Function: GET_PENDING_APPROVERS
   -- Purpose: Returns formatted comma-separated list of active pending task approvers for a workflow
   ----------------------------------------------------------------------------------------------------------------------------------
   FUNCTION GET_PENDING_APPROVERS (
      P_WORKFLOW_ID IN NUMBER
   ) RETURN VARCHAR2 IS
      V_RES VARCHAR2(4000);
   BEGIN
      SELECT LISTAGG(ACTUAL_OWNER, ', ') WITHIN GROUP (ORDER BY CREATED_ON)
        INTO V_RES
        FROM (SELECT ACTUAL_OWNER, CREATED_ON
                FROM APEX_TASKS
               WHERE WORKFLOW_ID = P_WORKFLOW_ID
                 AND STATE_CODE IN ('ASSIGNED', 'UNASSIGNED')
              UNION
              SELECT ACTUAL_OWNER, CREATED_ON
                FROM GEN_WF_TASK_LOG
               WHERE WORKFLOW_ID = P_WORKFLOW_ID
                 AND STATE_CODE IN ('ASSIGNED', 'UNASSIGNED'));
      RETURN V_RES;
   EXCEPTION
      WHEN OTHERS THEN
         RETURN NULL;
   END GET_PENDING_APPROVERS;

   ----------------------------------------------------------------------------------------------------------------------------------
   -- Procedure: PURGE_LOGS
   -- Purpose: Retention cleanup - purges logs older than N days
   ----------------------------------------------------------------------------------------------------------------------------------
   PROCEDURE PURGE_LOGS (
      P_DAYS_TO_KEEP IN NUMBER DEFAULT 90
   ) IS
   BEGIN
      DELETE FROM GEN_WF_TASK_LOG
       WHERE CREATED_ON < SYSTIMESTAMP - NUMTODSINTERVAL(P_DAYS_TO_KEEP, 'DAY');

      DELETE FROM GEN_WF_WORKFLOW_LOG
       WHERE START_TIME < SYSTIMESTAMP - NUMTODSINTERVAL(P_DAYS_TO_KEEP, 'DAY');

      DELETE FROM GEN_WF_ERRORS
       WHERE ERROR_DATE < SYSTIMESTAMP - NUMTODSINTERVAL(P_DAYS_TO_KEEP, 'DAY');

      COMMIT;
   EXCEPTION
      WHEN OTHERS THEN
         ROLLBACK;
         LOG_ERROR(
            P_CALLING_PROC  => 'GEN_WF_LOG_PKG.PURGE_LOGS',
            P_ERROR_CODE    => TO_CHAR(SQLCODE),
            P_ERROR_MESSAGE => SQLERRM,
            P_ERROR_STACK   => DBMS_UTILITY.FORMAT_ERROR_BACKTRACE
         );
   END PURGE_LOGS;

   ----------------------------------------------------------------------------------------------------------------------------------
   -- Procedure: CREATE_APEX_SESSION
   -- Purpose: Creates an APEX session for background jobs/scripts
   ----------------------------------------------------------------------------------------------------------------------------------
   PROCEDURE CREATE_APEX_SESSION (
      P_APP_ID       IN NUMBER,
      P_PAGE_ID      IN NUMBER DEFAULT 1,
      P_USERNAME     IN VARCHAR2,
      P_ENABLE_DEBUG IN BOOLEAN DEFAULT FALSE
   ) AS
   BEGIN
      APEX_SESSION.CREATE_SESSION(
         P_APP_ID                   => P_APP_ID,
         P_PAGE_ID                  => P_PAGE_ID,
         P_USERNAME                 => UPPER(P_USERNAME),
         P_CALL_POST_AUTHENTICATION => TRUE
      );

      IF P_ENABLE_DEBUG THEN
         APEX_DEBUG.ENABLE(APEX_DEBUG.C_LOG_LEVEL_INFO);
      END IF;
   EXCEPTION
      WHEN OTHERS THEN
         LOG_ERROR(
            P_CALLING_PROC  => 'GEN_WF_LOG_PKG.CREATE_APEX_SESSION',
            P_ERROR_CODE    => TO_CHAR(SQLCODE),
            P_ERROR_MESSAGE => SQLERRM,
            P_ERROR_STACK   => DBMS_UTILITY.FORMAT_ERROR_BACKTRACE
         );
   END CREATE_APEX_SESSION;

END GEN_WF_LOG_PKG;
/
