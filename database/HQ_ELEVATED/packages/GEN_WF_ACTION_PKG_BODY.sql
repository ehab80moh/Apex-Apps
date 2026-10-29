
  CREATE OR REPLACE EDITIONABLE PACKAGE BODY "HQ_ELEVATED"."GEN_WF_ACTION_PKG" AS

   ----------------------------------------------------------------------------------------------------------------------------------
   -- Private Helper: Safely insert task log dynamically
   ----------------------------------------------------------------------------------------------------------------------------------
   PROCEDURE LOG_TASK_EXECUTION (
      P_TASK_ID IN NUMBER
   ) IS
   BEGIN
      IF P_TASK_ID IS NOT NULL THEN
         BEGIN
            EXECUTE IMMEDIATE 'BEGIN epromhq.insert_task_log(:1); END;' USING P_TASK_ID;
         EXCEPTION
            WHEN OTHERS THEN
               NULL; -- Ignore log failure if procedure does not exist in context
         END;
      END IF;
   END LOG_TASK_EXECUTION;

   ----------------------------------------------------------------------------------------------------------------------------------
   -- Procedure: APPROVE_REQUEST
   ----------------------------------------------------------------------------------------------------------------------------------
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
   ) IS
      L_NEXT_SEQ NUMBER := 0;
      V_BODY     VARCHAR2(999);
      L_USER     VARCHAR2(255) := NVL(P_APP_USER, NVL(SYS_CONTEXT('APEX$SESSION', 'APP_USER'), USER));
   BEGIN
      -- 1. Check if there is a next step in the hierarchy
      L_NEXT_SEQ := CENTRAL.GET_NEXT_APPR_SEQ(
         P_EMP_ID      => P_EMP_ID,
         P_REQ_TYPE_ID => P_REQUEST_TYPE_ID,
         P_CURRENT_SEQ => P_SEQ_NO
      );

      -- 2. Log approval step
      CENTRAL.ADD_APR_LOG(
         P_REQUEST_TYPE_ID => P_REQUEST_TYPE_ID,
         P_REQUEST_ID      => P_REQUEST_ID,
         P_APPROVER_TYPE   => 'FYA',
         P_APPROVER        => L_USER,
         P_SEQ             => P_SEQ_NO
      );

      IF L_NEXT_SEQ > 0 THEN
         -- Intermediate step: Mark current notification done (New task creation omitted per requirements)
         CENTRAL.XXAPEX_EMP_NOTIFICATIONS.MARK_NOTIFICATION_DONE(
            P_TASK_ID => P_TASK_ID
         );
      ELSE
         -- Final step: Update target request table
         IF P_REQUEST_TYPE_ID = 59 THEN -- Leave Request
            UPDATE EPROMHQ.HRF_EMP_LEAVE_REQUEST
               SET TASK_IDS = P_TASK_IDS || '->' || TO_CHAR(P_TASK_ID),
                   UPDATED_BY = UPDATED_BY || '->' || P_UPDATED_BY || '->' || L_USER,
                   APPROVED = 1,
                   LAST_APPROVAL_DATE = SYSDATE
             WHERE REQUEST_ID = P_REQUEST_ID;

         ELSIF P_REQUEST_TYPE_ID = 61 THEN -- Permission Request
            UPDATE EPROMHQ.HRF_EMP_PERMISSION_REQUEST
               SET TASK_IDS = P_TASK_IDS || '->' || TO_CHAR(P_TASK_ID),
                   UPDATED_BY = UPDATED_BY || P_UPDATED_BY || '->' || L_USER,
                   APPROVED = 1,
                   LAST_APPROVAL_DATE = SYSDATE
             WHERE REQUEST_ID = P_REQUEST_ID;

         ELSIF P_REQUEST_TYPE_ID = 76 THEN -- Overtime Request
            UPDATE EPROMHQ.HRF_EMP_OVERTIME_REQUEST
               SET TASK_IDS = P_TASK_IDS || '->' || TO_CHAR(P_TASK_ID),
                   UPDATED_BY = UPDATED_BY || P_UPDATED_BY || '->' || L_USER,
                   APPROVED = 1,
                   LAST_APPROVAL_DATE = SYSDATE
             WHERE REQUEST_ID = P_REQUEST_ID;

         ELSE -- Mission Request or Dynamic Request Type
            UPDATE EPROMHQ.HRF_EMP_MISSION_REQUEST
               SET TASK_IDS = P_TASK_IDS || '->' || TO_CHAR(P_TASK_ID),
                   UPDATED_BY = UPDATED_BY || P_UPDATED_BY || '->' || L_USER,
                   APPROVED = 1,
                   LAST_APPROVAL_DATE = SYSDATE
             WHERE REQUEST_ID = P_REQUEST_ID;
         END IF;

         -- Dispatch approval notification to user
         BEGIN
            V_BODY := CENTRAL.XXAPEX_EMP_NOTIFICATIONS.GENERATE_NOTIFICATION_TEXT2(
               P_EMP_ID          => P_EMP_ID,
               P_REQUEST_TYPE_ID => P_REQUEST_TYPE_ID,
               P_REQUEST_ID      => P_REQUEST_ID,
               P_STATUS          => 3
            );

            CENTRAL.XXAPEX_EMP_NOTIFICATIONS.ADD_NOTIFICATION(
               P_EMP_ID    => P_EMP_ID,
               P_TITLE     => P_TASK_SUBJECT,
               P_BODY      => V_BODY,
               P_APP_ID    => 104,
               P_PAGE_ID   => 100,
               P_TASK_ID   => P_TASK_ID,
               P_INITIATOR => P_TASK_INITIATOR
            );

            CENTRAL.XXAPEX_EMP_NOTIFICATIONS.MARK_NOTIFICATION_DONE(
               P_TASK_ID => P_TASK_ID
            );

            CENTRAL.ADD_FYI_LOG_NOTIFY(
               P_REQUEST_ID      => P_REQUEST_ID,
               P_REQUEST_TYPE_ID => P_REQUEST_TYPE_ID,
               P_EMP_ID          => P_EMP_ID,
               P_TASK_SUBJECT    => P_TASK_SUBJECT,
               P_MESSAGE         => V_BODY,
               P_TASK_ID         => P_TASK_ID
            );
         EXCEPTION
            WHEN OTHERS THEN
               CENTRAL.LOG_ERR_TABLE_AND_JSON(SQLERRM, 'gen_wf_action_pkg.approve_request.notify', FALSE);
         END;
      END IF;

      LOG_TASK_EXECUTION(P_TASK_ID);
   EXCEPTION
      WHEN OTHERS THEN
         CENTRAL.LOG_ERR_TABLE_AND_JSON(SQLERRM, 'gen_wf_action_pkg.approve_request', FALSE);
         RAISE;
   END APPROVE_REQUEST;

   ----------------------------------------------------------------------------------------------------------------------------------
   -- Procedure: REJECT_REQUEST
   ----------------------------------------------------------------------------------------------------------------------------------
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
   ) IS
      V_BODY VARCHAR2(999);
      L_USER VARCHAR2(255) := NVL(P_APP_USER, NVL(SYS_CONTEXT('APEX$SESSION', 'APP_USER'), USER));
   BEGIN
      IF P_REQUEST_TYPE_ID = 59 THEN -- Leave Request
         UPDATE EPROMHQ.HRF_EMP_LEAVE_REQUEST
            SET TASK_IDS = TASK_IDS || P_TASK_IDS || '->' || TO_CHAR(P_TASK_ID),
                UPDATED_BY = UPDATED_BY || P_UPDATED_BY || '->' || L_USER,
                APPROVED = 2,
                LAST_APPROVAL_DATE = SYSDATE
          WHERE REQUEST_ID = P_REQUEST_ID;

      ELSIF P_REQUEST_TYPE_ID = 61 THEN -- Permission Request
         UPDATE EPROMHQ.HRF_EMP_PERMISSION_REQUEST
            SET TASK_IDS = TASK_IDS || P_TASK_IDS || '->' || TO_CHAR(P_TASK_ID),
                UPDATED_BY = UPDATED_BY || P_UPDATED_BY || '->' || L_USER,
                APPROVED = 2,
                LAST_APPROVAL_DATE = SYSDATE
          WHERE REQUEST_ID = P_REQUEST_ID;

      ELSIF P_REQUEST_TYPE_ID = 76 THEN -- Overtime Request
         UPDATE EPROMHQ.HRF_EMP_OVERTIME_REQUEST
            SET TASK_IDS = TASK_IDS || P_TASK_IDS || '->' || TO_CHAR(P_TASK_ID),
                UPDATED_BY = UPDATED_BY || P_UPDATED_BY || '->' || L_USER,
                APPROVED = 2,
                LAST_APPROVAL_DATE = SYSDATE
          WHERE REQUEST_ID = P_REQUEST_ID;

      ELSE -- Mission Request
         UPDATE EPROMHQ.HRF_EMP_MISSION_REQUEST
            SET TASK_IDS = TASK_IDS || P_TASK_IDS || '->' || TO_CHAR(P_TASK_ID),
                UPDATED_BY = UPDATED_BY || P_UPDATED_BY || '->' || L_USER,
                APPROVED = 2,
                LAST_APPROVAL_DATE = SYSDATE
          WHERE REQUEST_ID = P_REQUEST_ID;
      END IF;

      BEGIN
         V_BODY := CENTRAL.XXAPEX_EMP_NOTIFICATIONS.GENERATE_NOTIFICATION_TEXT2(
            P_EMP_ID          => P_EMP_ID,
            P_REQUEST_TYPE_ID => P_REQUEST_TYPE_ID,
            P_REQUEST_ID      => P_REQUEST_ID,
            P_STATUS          => 4
         );

         CENTRAL.XXAPEX_EMP_NOTIFICATIONS.ADD_NOTIFICATION(
            P_EMP_ID    => P_EMP_ID,
            P_TITLE     => P_TASK_SUBJECT,
            P_BODY      => V_BODY,
            P_APP_ID    => 104,
            P_PAGE_ID   => 100,
            P_TASK_ID   => P_TASK_ID,
            P_INITIATOR => P_TASK_INITIATOR
         );

         CENTRAL.XXAPEX_EMP_NOTIFICATIONS.MARK_NOTIFICATION_REJECTED(
            P_TASK_ID => P_TASK_ID
         );
      EXCEPTION
         WHEN OTHERS THEN
            CENTRAL.LOG_ERR_TABLE_AND_JSON(SQLERRM, 'gen_wf_action_pkg.reject_request.notify', FALSE);
      END;

      LOG_TASK_EXECUTION(P_TASK_ID);
   EXCEPTION
      WHEN OTHERS THEN
         CENTRAL.LOG_ERR_TABLE_AND_JSON(SQLERRM, 'gen_wf_action_pkg.reject_request', FALSE);
         RAISE;
   END REJECT_REQUEST;

   ----------------------------------------------------------------------------------------------------------------------------------
   -- Procedure: CANCEL_REQUEST
   ----------------------------------------------------------------------------------------------------------------------------------
   PROCEDURE CANCEL_REQUEST (
      P_REQUEST_TYPE_ID IN NUMBER,
      P_REQUEST_ID      IN NUMBER,
      P_TASK_ID         IN NUMBER,
      P_REASON          IN VARCHAR2 DEFAULT NULL
   ) IS
   BEGIN
      IF P_REQUEST_TYPE_ID = 104 THEN
         ITR_REQUEST_ACTION_PKG.CANCEL_BY_COORDINATOR(
            P_REQUEST_ID => P_REQUEST_ID,
            P_TASK_ID    => P_TASK_ID,
            P_REASON     => P_REASON,
            P_ACTOR      => NVL(V('APP_USER'), USER)
         );
      ELSIF P_REQUEST_TYPE_ID = 59 THEN
         UPDATE EPROMHQ.HRF_EMP_LEAVE_REQUEST SET APPROVED = 3 WHERE REQUEST_ID = P_REQUEST_ID;
      ELSIF P_REQUEST_TYPE_ID = 61 THEN
         UPDATE EPROMHQ.HRF_EMP_PERMISSION_REQUEST SET APPROVED = 3 WHERE REQUEST_ID = P_REQUEST_ID;
      ELSIF P_REQUEST_TYPE_ID = 76 THEN
         UPDATE EPROMHQ.HRF_EMP_OVERTIME_REQUEST SET APPROVED = 3 WHERE REQUEST_ID = P_REQUEST_ID;
      ELSE
         UPDATE EPROMHQ.HRF_EMP_MISSION_REQUEST SET APPROVED = 3 WHERE REQUEST_ID = P_REQUEST_ID;
      END IF;

      IF P_REQUEST_TYPE_ID <> 104 THEN
         BEGIN
            CENTRAL.XXAPEX_EMP_NOTIFICATIONS.MARK_NOTIFICATION_CANCELLED(
               P_TASK_ID => P_TASK_ID
            );
         EXCEPTION
            WHEN OTHERS THEN
               CENTRAL.LOG_ERR_TABLE_AND_JSON(SQLERRM, 'gen_wf_action_pkg.cancel_request.notify', FALSE);
         END;

         LOG_TASK_EXECUTION(P_TASK_ID);
      END IF;
   EXCEPTION
      WHEN OTHERS THEN
         IF P_REQUEST_TYPE_ID <> 104 THEN
            CENTRAL.LOG_ERR_TABLE_AND_JSON(SQLERRM, 'gen_wf_action_pkg.cancel_request', FALSE);
         END IF;
         RAISE;
   END CANCEL_REQUEST;

   ----------------------------------------------------------------------------------------------------------------------------------
   -- Procedure: APPROVE_CANCELLATION
   ----------------------------------------------------------------------------------------------------------------------------------
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
   ) IS
      L_NEXT_SEQ NUMBER := 0;
      V_BODY     VARCHAR2(999);
      L_USER     VARCHAR2(255) := NVL(P_APP_USER, NVL(SYS_CONTEXT('APEX$SESSION', 'APP_USER'), USER));
   BEGIN
      L_NEXT_SEQ := CENTRAL.GET_NEXT_APPR_SEQ(
         P_EMP_ID      => P_EMP_ID,
         P_REQ_TYPE_ID => P_REQUEST_TYPE_ID,
         P_CURRENT_SEQ => P_SEQ_NO
      );

      CENTRAL.ADD_APR_LOG(
         P_REQUEST_TYPE_ID => P_REQUEST_TYPE_ID,
         P_REQUEST_ID      => P_REQUEST_ID,
         P_APPROVER_TYPE   => 'FYA',
         P_APPROVER        => L_USER,
         P_SEQ             => P_SEQ_NO
      );

      IF L_NEXT_SEQ > 0 THEN
         CENTRAL.XXAPEX_EMP_NOTIFICATIONS.MARK_NOTIFICATION_DONE(
            P_TASK_ID => P_TASK_ID
         );
      ELSE
         IF P_REQUEST_TYPE_ID = 59 THEN
            UPDATE EPROMHQ.HRF_EMP_LEAVE_REQUEST
               SET TASK_IDS = P_TASK_IDS || 'd->' || TO_CHAR(P_TASK_ID),
                   UPDATED_BY = UPDATED_BY || 'd->' || P_UPDATED_BY || 'd->' || L_USER,
                   DELETE_APPROVED = 1
             WHERE REQUEST_ID = P_REQUEST_ID;

         ELSIF P_REQUEST_TYPE_ID = 61 THEN
            UPDATE EPROMHQ.HRF_EMP_PERMISSION_REQUEST
               SET TASK_IDS = P_TASK_IDS || 'd->' || TO_CHAR(P_TASK_ID),
                   UPDATED_BY = UPDATED_BY || 'd->' || P_UPDATED_BY || 'd->' || L_USER,
                   DELETE_APPROVED = 1
             WHERE REQUEST_ID = P_REQUEST_ID;

         ELSIF P_REQUEST_TYPE_ID = 76 THEN
            UPDATE EPROMHQ.HRF_EMP_OVERTIME_REQUEST
               SET TASK_IDS = P_TASK_IDS || 'd->' || TO_CHAR(P_TASK_ID),
                   UPDATED_BY = UPDATED_BY || P_UPDATED_BY || 'd->' || L_USER,
                   DELETE_APPROVED = 1
             WHERE REQUEST_ID = P_REQUEST_ID;

         ELSE
            UPDATE EPROMHQ.HRF_EMP_MISSION_REQUEST
               SET TASK_IDS = P_TASK_IDS || '->' || TO_CHAR(P_TASK_ID),
                   UPDATED_BY = UPDATED_BY || 'd->' || P_UPDATED_BY || 'd->' || L_USER,
                   DELETE_APPROVED = 1,
                   LAST_APPROVAL_DATE = SYSDATE
             WHERE REQUEST_ID = P_REQUEST_ID;
         END IF;

         BEGIN
            V_BODY := CENTRAL.XXAPEX_EMP_NOTIFICATIONS.GENERATE_NOTIFICATION_TEXT2(
               P_EMP_ID          => P_EMP_ID,
               P_REQUEST_TYPE_ID => P_REQUEST_TYPE_ID,
               P_REQUEST_ID      => P_REQUEST_ID,
               P_STATUS          => 7
            );

            CENTRAL.XXAPEX_EMP_NOTIFICATIONS.ADD_NOTIFICATION(
               P_EMP_ID    => P_EMP_ID,
               P_TITLE     => P_TASK_SUBJECT,
               P_BODY      => V_BODY,
               P_APP_ID    => 104,
               P_PAGE_ID   => 100,
               P_TASK_ID   => P_TASK_ID,
               P_INITIATOR => P_TASK_INITIATOR
            );

            CENTRAL.XXAPEX_EMP_NOTIFICATIONS.MARK_NOTIFICATION_DONE(
               P_TASK_ID => P_TASK_ID
            );

            CENTRAL.ADD_FYI_LOG_NOTIFY(
               P_REQUEST_ID      => P_REQUEST_ID,
               P_REQUEST_TYPE_ID => P_REQUEST_TYPE_ID,
               P_EMP_ID          => P_EMP_ID,
               P_TASK_SUBJECT    => P_TASK_SUBJECT,
               P_MESSAGE         => V_BODY,
               P_TASK_ID         => P_TASK_ID
            );
         EXCEPTION
            WHEN OTHERS THEN
               CENTRAL.LOG_ERR_TABLE_AND_JSON(SQLERRM, 'gen_wf_action_pkg.approve_cancellation.notify', FALSE);
         END;
      END IF;

      LOG_TASK_EXECUTION(P_TASK_ID);
   EXCEPTION
      WHEN OTHERS THEN
         CENTRAL.LOG_ERR_TABLE_AND_JSON(SQLERRM, 'gen_wf_action_pkg.approve_cancellation', FALSE);
         RAISE;
   END APPROVE_CANCELLATION;

   ----------------------------------------------------------------------------------------------------------------------------------
   -- Procedure: REJECT_CANCELLATION
   ----------------------------------------------------------------------------------------------------------------------------------
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
   ) IS
      L_USER VARCHAR2(255) := NVL(P_APP_USER, NVL(SYS_CONTEXT('APEX$SESSION', 'APP_USER'), USER));
   BEGIN
      IF P_REQUEST_TYPE_ID = 59 THEN
         UPDATE EPROMHQ.HRF_EMP_LEAVE_REQUEST
            SET TASK_IDS = TASK_IDS || P_TASK_IDS || 'd->' || TO_CHAR(P_TASK_ID),
                UPDATED_BY = UPDATED_BY || P_UPDATED_BY || 'd->' || L_USER,
                DELETE_APPROVED = 2
          WHERE REQUEST_ID = P_REQUEST_ID;

      ELSIF P_REQUEST_TYPE_ID = 61 THEN
         UPDATE EPROMHQ.HRF_EMP_PERMISSION_REQUEST
            SET TASK_IDS = TASK_IDS || P_TASK_IDS || 'd->' || TO_CHAR(P_TASK_ID),
                UPDATED_BY = UPDATED_BY || P_UPDATED_BY || 'd->' || L_USER,
                DELETE_APPROVED = 2
          WHERE REQUEST_ID = P_REQUEST_ID;

      ELSIF P_REQUEST_TYPE_ID = 76 THEN
         UPDATE EPROMHQ.HRF_EMP_OVERTIME_REQUEST
            SET TASK_IDS = TASK_IDS || P_TASK_IDS || 'd->' || TO_CHAR(P_TASK_ID),
                UPDATED_BY = UPDATED_BY || P_UPDATED_BY || 'd->' || L_USER,
                DELETE_APPROVED = 2
          WHERE REQUEST_ID = P_REQUEST_ID;

      ELSE
         UPDATE EPROMHQ.HRF_EMP_MISSION_REQUEST
            SET TASK_IDS = TASK_IDS || P_TASK_IDS || '->' || TO_CHAR(P_TASK_ID),
                UPDATED_BY = UPDATED_BY || P_UPDATED_BY || '->' || L_USER,
                DELETE_APPROVED = 2,
                LAST_APPROVAL_DATE = SYSDATE
          WHERE REQUEST_ID = P_REQUEST_ID;
      END IF;

      BEGIN
         CENTRAL.XXAPEX_EMP_NOTIFICATIONS.ADD_NOTIFICATION(
            P_EMP_ID    => P_EMP_ID,
            P_TITLE     => P_TASK_SUBJECT,
            P_BODY      => 'تم رفض ' || P_TASK_SUBJECT,
            P_APP_ID    => 104,
            P_PAGE_ID   => 100,
            P_TASK_ID   => P_TASK_ID,
            P_INITIATOR => P_TASK_INITIATOR
         );

         CENTRAL.XXAPEX_EMP_NOTIFICATIONS.MARK_NOTIFICATION_REJECTED(
            P_TASK_ID => P_TASK_ID
         );
      EXCEPTION
         WHEN OTHERS THEN
            CENTRAL.LOG_ERR_TABLE_AND_JSON(SQLERRM, 'gen_wf_action_pkg.reject_cancellation.notify', FALSE);
      END;

      LOG_TASK_EXECUTION(P_TASK_ID);
   EXCEPTION
      WHEN OTHERS THEN
         CENTRAL.LOG_ERR_TABLE_AND_JSON(SQLERRM, 'gen_wf_action_pkg.reject_cancellation', FALSE);
         RAISE;
   END REJECT_CANCELLATION;

   ----------------------------------------------------------------------------------------------------------------------------------
   -- Procedure: CANCEL_CANCELLATION
   ----------------------------------------------------------------------------------------------------------------------------------
   PROCEDURE CANCEL_CANCELLATION (
      P_REQUEST_TYPE_ID IN NUMBER,
      P_REQUEST_ID      IN NUMBER,
      P_TASK_ID         IN NUMBER
   ) IS
   BEGIN
      IF P_REQUEST_TYPE_ID = 59 THEN
         UPDATE EPROMHQ.HRF_EMP_LEAVE_REQUEST SET DELETE_APPROVED = 3 WHERE REQUEST_ID = P_REQUEST_ID;
      ELSIF P_REQUEST_TYPE_ID = 61 THEN
         UPDATE EPROMHQ.HRF_EMP_PERMISSION_REQUEST SET DELETE_APPROVED = 3 WHERE REQUEST_ID = P_REQUEST_ID;
      ELSIF P_REQUEST_TYPE_ID = 76 THEN
         UPDATE EPROMHQ.HRF_EMP_OVERTIME_REQUEST SET DELETE_APPROVED = 3 WHERE REQUEST_ID = P_REQUEST_ID;
      ELSE
         UPDATE EPROMHQ.HRF_EMP_MISSION_REQUEST SET DELETE_APPROVED = 3 WHERE REQUEST_ID = P_REQUEST_ID;
      END IF;

      BEGIN
         CENTRAL.XXAPEX_EMP_NOTIFICATIONS.MARK_NOTIFICATION_CANCELLED(
            P_TASK_ID => P_TASK_ID
         );
      EXCEPTION
         WHEN OTHERS THEN
            CENTRAL.LOG_ERR_TABLE_AND_JSON(SQLERRM, 'gen_wf_action_pkg.cancel_cancellation.notify', FALSE);
      END;

      LOG_TASK_EXECUTION(P_TASK_ID);
   EXCEPTION
      WHEN OTHERS THEN
         CENTRAL.LOG_ERR_TABLE_AND_JSON(SQLERRM, 'gen_wf_action_pkg.cancel_cancellation', FALSE);
         RAISE;
   END CANCEL_CANCELLATION;

   ----------------------------------------------------------------------------------------------------------------------------------
   -- Procedure: PROCESS_ACTION (Master Dispatcher)
   ----------------------------------------------------------------------------------------------------------------------------------
   PROCEDURE PROCESS_ACTION (
      P_REQUEST_TYPE_ID IN NUMBER,
      P_ACTION          IN VARCHAR2,
      P_REQUEST_ID      IN NUMBER,
      P_EMP_ID          IN NUMBER,
      P_TASK_ID         IN NUMBER,
      P_APP_USER        IN VARCHAR2 DEFAULT NULL,
      P_SEQ_NO          IN NUMBER   DEFAULT 1,
      P_TASK_IDS        IN VARCHAR2 DEFAULT NULL,
      P_UPDATED_BY      IN VARCHAR2 DEFAULT NULL,
      P_TASK_SUBJECT    IN VARCHAR2 DEFAULT NULL,
      P_TASK_INITIATOR  IN VARCHAR2 DEFAULT NULL
   ) IS
      L_ACTION VARCHAR2(50) := UPPER(TRIM(P_ACTION));
   BEGIN
      IF L_ACTION IN ('APPROVE', 'APPROVED', 'ACCEPT') THEN
         APPROVE_REQUEST(
            P_REQUEST_TYPE_ID => P_REQUEST_TYPE_ID,
            P_REQUEST_ID      => P_REQUEST_ID,
            P_EMP_ID          => P_EMP_ID,
            P_TASK_ID         => P_TASK_ID,
            P_APP_USER        => P_APP_USER,
            P_SEQ_NO          => P_SEQ_NO,
            P_TASK_IDS        => P_TASK_IDS,
            P_UPDATED_BY      => P_UPDATED_BY,
            P_TASK_SUBJECT    => P_TASK_SUBJECT,
            P_TASK_INITIATOR  => P_TASK_INITIATOR
         );

      ELSIF L_ACTION IN ('REJECT', 'REJECTED') THEN
         REJECT_REQUEST(
            P_REQUEST_TYPE_ID => P_REQUEST_TYPE_ID,
            P_REQUEST_ID      => P_REQUEST_ID,
            P_EMP_ID          => P_EMP_ID,
            P_TASK_ID         => P_TASK_ID,
            P_APP_USER        => P_APP_USER,
            P_TASK_IDS        => P_TASK_IDS,
            P_UPDATED_BY      => P_UPDATED_BY,
            P_TASK_SUBJECT    => P_TASK_SUBJECT,
            P_TASK_INITIATOR  => P_TASK_INITIATOR
         );

      ELSIF L_ACTION IN ('CANCEL', 'CANCELLED') THEN
         CANCEL_REQUEST(
            P_REQUEST_TYPE_ID => P_REQUEST_TYPE_ID,
            P_REQUEST_ID      => P_REQUEST_ID,
            P_TASK_ID         => P_TASK_ID
         );

      ELSIF L_ACTION IN ('COMPLETE', 'COMPLETED', 'DONE') THEN
         -- APEX action tasks may complete without an outcome.  Their workflow
         -- activity already performed the business update, so completion is a
         -- successful no-op in the shared dispatcher.
         NULL;

      ELSIF L_ACTION IN ('CANCEL_APPROVE', 'APPROVE_CANCEL') THEN
         APPROVE_CANCELLATION(
            P_REQUEST_TYPE_ID => P_REQUEST_TYPE_ID,
            P_REQUEST_ID      => P_REQUEST_ID,
            P_EMP_ID          => P_EMP_ID,
            P_TASK_ID         => P_TASK_ID,
            P_APP_USER        => P_APP_USER,
            P_SEQ_NO          => P_SEQ_NO,
            P_TASK_IDS        => P_TASK_IDS,
            P_UPDATED_BY      => P_UPDATED_BY,
            P_TASK_SUBJECT    => P_TASK_SUBJECT,
            P_TASK_INITIATOR  => P_TASK_INITIATOR
         );

      ELSIF L_ACTION IN ('CANCEL_REJECT', 'REJECT_CANCEL') THEN
         REJECT_CANCELLATION(
            P_REQUEST_TYPE_ID => P_REQUEST_TYPE_ID,
            P_REQUEST_ID      => P_REQUEST_ID,
            P_EMP_ID          => P_EMP_ID,
            P_TASK_ID         => P_TASK_ID,
            P_APP_USER        => P_APP_USER,
            P_TASK_IDS        => P_TASK_IDS,
            P_UPDATED_BY      => P_UPDATED_BY,
            P_TASK_SUBJECT    => P_TASK_SUBJECT,
            P_TASK_INITIATOR  => P_TASK_INITIATOR
         );

      ELSIF L_ACTION IN ('CANCEL_CANCEL') THEN
         CANCEL_CANCELLATION(
            P_REQUEST_TYPE_ID => P_REQUEST_TYPE_ID,
            P_REQUEST_ID      => P_REQUEST_ID,
            P_TASK_ID         => P_TASK_ID
         );

      ELSE
         RAISE_APPLICATION_ERROR(-20001, 'Unsupported workflow action: ' || P_ACTION);
      END IF;
   END PROCESS_ACTION;

END GEN_WF_ACTION_PKG;
/
