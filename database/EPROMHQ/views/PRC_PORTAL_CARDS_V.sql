
  CREATE OR REPLACE FORCE EDITIONABLE VIEW "EPROMHQ"."PRC_PORTAL_CARDS_V" ("CONTEXT_KIND", "TASK_ID", "CYCLE_ID", "SOURCE_KEY", "REQUESTED_BY", "STARTED_AT", "TOTAL_VOTERS", "APPROVED_COUNT", "REJECTED_COUNT", "REQUEST_TYPE_NAME", "COMMITTEE_NAME", "DISPLAY_STATUS", "ROLE_NAME", "SPECIALTY", "CARD_TITLE", "STATUS_LABEL", "STATUS_CSS") AS
  WITH cycle_data AS (
    SELECT c.cycle_id,c.source_key,c.requested_by,c.started_at,
           c.total_voters,c.approved_count,c.rejected_count,
           CASE c.source_type_id WHEN 44 THEN 'قرض اجتماعي' WHEN 43 THEN 'قرض زواج'
                WHEN 45 THEN 'طلب عمرة' WHEN 46 THEN 'طلب حج' ELSE 'طلب خدمات اجتماعية' END request_type_name,
           k.committee_name,
           CASE WHEN c.cycle_status='PENDING' AND c.total_voters>0
                     AND NVL(c.approved_count,0)+NVL(c.rejected_count,0)>=c.total_voters
                THEN 'CHAIR_PENDING' ELSE c.cycle_status END display_status
      FROM prc_approval_cycles c
      JOIN prc_committee_versions cv ON cv.version_id=c.version_id
      JOIN prc_committees k ON k.committee_id=cv.committee_id
     WHERE c.source_app_id=105 AND c.source_entity_code='PRF_LOANS_REQUEST'
       AND EXISTS (SELECT 1 FROM prf_loans_request r
                    WHERE r.request_id=TO_NUMBER(c.source_key DEFAULT NULL ON CONVERSION ERROR)
                      AND r.request_type_id=TO_CHAR(c.source_type_id))
), card_data AS (
    SELECT CAST('REQUEST' AS VARCHAR2(20)) context_kind,CAST(NULL AS NUMBER) task_id,
           c.cycle_id,c.source_key,c.requested_by,c.started_at,c.total_voters,c.approved_count,c.rejected_count,
           c.request_type_name,c.committee_name,c.display_status,
           CAST(NULL AS VARCHAR2(255)) role_name,CAST(NULL AS VARCHAR2(255)) specialty,
           'طلب لجنة — '||c.request_type_name||' رقم '||c.source_key card_title
      FROM cycle_data c WHERE UPPER(c.requested_by)=UPPER(V('APP_USER'))
    UNION ALL
    SELECT CAST('MEMBER_TASK' AS VARCHAR2(20)),v.task_id,
           c.cycle_id,c.source_key,c.requested_by,c.started_at,c.total_voters,c.approved_count,c.rejected_count,
           c.request_type_name,c.committee_name,c.display_status,
           CAST(v.role_name_snapshot AS VARCHAR2(255)),CAST(v.specialty_snapshot AS VARCHAR2(255)),
           'مراجعة لجنة — '||c.request_type_name||' رقم '||c.source_key
      FROM cycle_data c JOIN prc_approval_voters v ON v.cycle_id=c.cycle_id
     WHERE UPPER(v.app_user)=UPPER(V('APP_USER')) AND v.task_id IS NOT NULL
    UNION ALL
    SELECT CAST('FINAL_TASK' AS VARCHAR2(20)),f.task_id,
           c.cycle_id,c.source_key,c.requested_by,c.started_at,c.total_voters,c.approved_count,c.rejected_count,
           c.request_type_name,c.committee_name,c.display_status,
           CAST('رئيس اللجنة — القرار النهائي' AS VARCHAR2(255)),
           CAST((SELECT MAX(v.specialty_snapshot) FROM prc_approval_voters v
                  WHERE v.cycle_id=c.cycle_id AND UPPER(v.app_user)=UPPER(f.app_user)) AS VARCHAR2(255)),
           'قرار رئيس اللجنة — '||c.request_type_name||' رقم '||c.source_key
      FROM cycle_data c JOIN prc_final_decisions f ON f.cycle_id=c.cycle_id
     WHERE UPPER(f.app_user)=UPPER(V('APP_USER')) AND f.task_id IS NOT NULL
)
SELECT d."CONTEXT_KIND",d."TASK_ID",d."CYCLE_ID",d."SOURCE_KEY",d."REQUESTED_BY",d."STARTED_AT",d."TOTAL_VOTERS",d."APPROVED_COUNT",d."REJECTED_COUNT",d."REQUEST_TYPE_NAME",d."COMMITTEE_NAME",d."DISPLAY_STATUS",d."ROLE_NAME",d."SPECIALTY",d."CARD_TITLE",
       CASE display_status WHEN 'PREPARING' THEN 'جارٍ تجهيز المهام'
            WHEN 'PENDING' THEN 'بانتظار آراء أعضاء اللجنة'
            WHEN 'CHAIR_PENDING' THEN 'بانتظار قرار رئيس اللجنة'
            WHEN 'APPROVED' THEN 'موافقة نهائية من اللجنة'
            WHEN 'REJECTED' THEN 'رفض نهائي من اللجنة'
            WHEN 'CANCELLED' THEN 'طلب ملغى' ELSE 'تعذر بدء المراجعة' END status_label,
       CASE display_status WHEN 'APPROVED' THEN 'u-success' WHEN 'REJECTED' THEN 'u-danger'
            WHEN 'CANCELLED' THEN 'u-color-29' WHEN 'FAILED' THEN 'u-danger' ELSE 'u-warning' END status_css
  FROM card_data d;
