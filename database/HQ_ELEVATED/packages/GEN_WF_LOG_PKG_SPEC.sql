
  CREATE OR REPLACE EDITIONABLE PACKAGE "HQ_ELEVATED"."GEN_WF_LOG_PKG" AS
   ----------------------------------------------------------------------------------------------------------------------------------
   -- Purpose: Generic Workflow & Human Task Logging Engine for Oracle APEX
   ----------------------------------------------------------------------------------------------------------------------------------

   -- Merges complete APEX workflow metadata, activities, variables, participants, and audit trail into GEN_WF_WORKFLOW_LOG
   PROCEDURE CAPTURE_WORKFLOW_LOG (
      P_WORKFLOW_ID IN NUMBER
   );

   -- Merges complete APEX task metadata, history, parameters, and participants into GEN_WF_TASK_LOG
   PROCEDURE CAPTURE_TASK_LOG (
      P_TASK_ID IN NUMBER
   );

   -- Convenience wrapper: Merges all tasks linked to a workflow ID into GEN_WF_TASK_LOG
   PROCEDURE CAPTURE_ALL_WF_TASKS (
      P_WORKFLOW_ID IN NUMBER
   );

   -- Autonomous transaction error logger (persists even if main transaction rolls back)
   PROCEDURE LOG_ERROR (
      P_CALLING_PROC  IN VARCHAR2,
      P_ERROR_CODE    IN VARCHAR2,
      P_ERROR_MESSAGE IN VARCHAR2,
      P_ERROR_STACK   IN CLOB DEFAULT NULL
   );

   -- Extracts a specific variable's value from the logged JSON array in GEN_WF_WORKFLOW_LOG
   FUNCTION GET_WORKFLOW_VARIABLE (
      P_WORKFLOW_ID   IN NUMBER,
      P_VAR_STATIC_ID IN VARCHAR2
   ) RETURN VARCHAR2;

   -- Extracts a specific task parameter's value from the logged JSON array in GEN_WF_TASK_LOG
   FUNCTION GET_TASK_PARAMETER (
      P_TASK_ID        IN NUMBER,
      P_PARAM_STATIC_ID IN VARCHAR2
   ) RETURN VARCHAR2;

   -- Returns formatted comma-separated list of active pending approvers for a workflow
   FUNCTION GET_PENDING_APPROVERS (
      P_WORKFLOW_ID IN NUMBER
   ) RETURN VARCHAR2;

   -- Retention cleanup: Purges logs older than N days from all 3 logging tables
   PROCEDURE PURGE_LOGS (
      P_DAYS_TO_KEEP IN NUMBER DEFAULT 90
   );

   -- Session Helper: Creates an APEX session for background jobs/scripts
   PROCEDURE CREATE_APEX_SESSION (
      P_APP_ID       IN NUMBER,
      P_PAGE_ID      IN NUMBER DEFAULT 1,
      P_USERNAME     IN VARCHAR2,
      P_ENABLE_DEBUG IN BOOLEAN DEFAULT FALSE
   );

END GEN_WF_LOG_PKG;
/
