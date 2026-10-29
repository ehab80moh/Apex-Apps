
  CREATE OR REPLACE EDITIONABLE PACKAGE "HQ_ELEVATED"."GEN_WF_ACTION_PKG" AS
   ----------------------------------------------------------------------------------------------------------------------------------
   -- Purpose: Unified Workflow Human Task Action Engine for HR Forms (App 115)
   --          Consolidates Approve, Reject, and Cancel actions for primary and cancellation requests.
   ----------------------------------------------------------------------------------------------------------------------------------

   -- Master Entry Point
   PROCEDURE PROCESS_ACTION (
      P_REQUEST_TYPE_ID IN NUMBER,
      P_ACTION          IN VARCHAR2, -- 'APPROVE', 'REJECT', 'CANCEL', 'COMPLETE', 'CANCEL_APPROVE', 'CANCEL_REJECT', 'CANCEL_CANCEL'
      P_REQUEST_ID      IN NUMBER,
      P_EMP_ID          IN NUMBER,
      P_TASK_ID         IN NUMBER,
      P_APP_USER        IN VARCHAR2 DEFAULT NULL,
      P_SEQ_NO          IN NUMBER   DEFAULT 1,
      P_TASK_IDS        IN VARCHAR2 DEFAULT NULL,
      P_UPDATED_BY      IN VARCHAR2 DEFAULT NULL,
      P_TASK_SUBJECT    IN VARCHAR2 DEFAULT NULL,
      P_TASK_INITIATOR  IN VARCHAR2 DEFAULT NULL
   );

   -- Dedicated Primary Request Actions
   PROCEDURE APPROVE_REQUEST (
      P_REQUEST_TYPE_ID IN NUMBER,
      P_REQUEST_ID      IN NUMBER,
      P_EMP_ID          IN NUMBER,
      P_TASK_ID         IN NUMBER,
      P_APP_USER        IN VARCHAR2 DEFAULT NULL,
      P_SEQ_NO          IN NUMBER   DEFAULT 1,
      P_TASK_IDS        IN VARCHAR2 DEFAULT NULL,
      P_UPDATED_BY      IN VARCHAR2 DEFAULT NULL,
      P_TASK_SUBJECT    IN VARCHAR2 DEFAULT NULL,
      P_TASK_INITIATOR  IN VARCHAR2 DEFAULT NULL
   );

   PROCEDURE REJECT_REQUEST (
      P_REQUEST_TYPE_ID IN NUMBER,
      P_REQUEST_ID      IN NUMBER,
      P_EMP_ID          IN NUMBER,
      P_TASK_ID         IN NUMBER,
      P_APP_USER        IN VARCHAR2 DEFAULT NULL,
      P_TASK_IDS        IN VARCHAR2 DEFAULT NULL,
      P_UPDATED_BY      IN VARCHAR2 DEFAULT NULL,
      P_TASK_SUBJECT    IN VARCHAR2 DEFAULT NULL,
      P_TASK_INITIATOR  IN VARCHAR2 DEFAULT NULL
   );

   PROCEDURE CANCEL_REQUEST (
      P_REQUEST_TYPE_ID IN NUMBER,
      P_REQUEST_ID      IN NUMBER,
      P_TASK_ID         IN NUMBER,
      P_REASON          IN VARCHAR2 DEFAULT NULL
   );

   -- Dedicated Cancellation Request Actions
   PROCEDURE APPROVE_CANCELLATION (
      P_REQUEST_TYPE_ID IN NUMBER,
      P_REQUEST_ID      IN NUMBER,
      P_EMP_ID          IN NUMBER,
      P_TASK_ID         IN NUMBER,
      P_APP_USER        IN VARCHAR2 DEFAULT NULL,
      P_SEQ_NO          IN NUMBER   DEFAULT 1,
      P_TASK_IDS        IN VARCHAR2 DEFAULT NULL,
      P_UPDATED_BY      IN VARCHAR2 DEFAULT NULL,
      P_TASK_SUBJECT    IN VARCHAR2 DEFAULT NULL,
      P_TASK_INITIATOR  IN VARCHAR2 DEFAULT NULL
   );

   PROCEDURE REJECT_CANCELLATION (
      P_REQUEST_TYPE_ID IN NUMBER,
      P_REQUEST_ID      IN NUMBER,
      P_EMP_ID          IN NUMBER,
      P_TASK_ID         IN NUMBER,
      P_APP_USER        IN VARCHAR2 DEFAULT NULL,
      P_TASK_IDS        IN VARCHAR2 DEFAULT NULL,
      P_UPDATED_BY      IN VARCHAR2 DEFAULT NULL,
      P_TASK_SUBJECT    IN VARCHAR2 DEFAULT NULL,
      P_TASK_INITIATOR  IN VARCHAR2 DEFAULT NULL
   );

   PROCEDURE CANCEL_CANCELLATION (
      P_REQUEST_TYPE_ID IN NUMBER,
      P_REQUEST_ID      IN NUMBER,
      P_TASK_ID         IN NUMBER
   );

END GEN_WF_ACTION_PKG;
/
