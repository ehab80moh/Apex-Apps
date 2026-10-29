
  CREATE OR REPLACE FORCE EDITIONABLE VIEW "HQ_ELEVATED"."VW_TRV_ALLOWANCE_47_HQ_ELEVATED" ("SELECT_ROW", "REQUEST_ID", "EMP_ID", "EMP_NAME", "SITE_CODE", "PROJECT", "GRADE_NUM", "TRIP_PURPOSE", "TRIP_LOCATION", "DATE_FROM", "start_time", "DATE_TO", "end_time", "NUMBER_DAYS", "PER_DIEM_RATE", "BB_75", "HB_50", "SA_100", "HOTEL_PLAN", "TOTAL_ALLOWANCE", "MEAL", "TRAVEL_EXPENSE", "LAST_APPROVAL_DATE", "STATUS", "TASK_IDS", "approval_manager", "APPROVAL_MANAGER_MSG", "approval_car", "APPROVAL_CAR_MSG", "approval_hotel", "APPROVAL_HOTEL_MSG", "APPROVAL_FINANCE_MSG", "Date_of_disbursement", "ATTACHED_FILE", "REQUEST_FINAL_STATUS", "APPROVAL_FINANCE", "NET_AMOUNT", "DATE_OF_ADMINISTRATOR") AS
  WITH exp AS (
  SELECT
      e.request_id,
      MAX(CASE WHEN e.hotels = '0' THEN 1 ELSE 0 END) AS bb_75_flag,  -- B.B 75%
      MAX(CASE WHEN e.hotels = '1' THEN 1 ELSE 0 END) AS hb_50_flag,  -- H.B 50%
--      MAX(CASE WHEN e.hotels = '2' THEN 1 ELSE 0 END) AS fb_0_flag,   -- F.B 0%
      MAX(CASE WHEN e.hotels = '3' THEN 1 ELSE 0 END) AS sa_100_flag  -- S.A 100%
  FROM EPROMHQ.TRV_EXPENSE e
  GROUP BY e.request_id
)
SELECT
'<input type="checkbox" class="row_checkbox" value="' || a.request_id || '"/>' AS select_row,
  a.request_id,
  a.emp_id,
  h.emp_name AS emp_name,
  h.SITE_CODE,
  h.PROJECT,
  TO_NUMBER(REGEXP_SUBSTR(TRIM(h.current_grade), '\d+$')) AS grade_num,
  a.trip_purpose,
  a.trip_location,
  a.date_from,
  a.start_time,
  a.date_to,
  a.end_time,
  TRUNC((a.date_to - a.date_from) + 1) AS number_days,
  a.per_diem_rate,

  NVL(ex.bb_75_flag, 0) AS bb_75,
  NVL(ex.hb_50_flag, 0) AS hb_50,
--  NVL(ex.fb_0_flag, 0)  AS fb_0,
  NVL(ex.sa_100_flag, 0) AS sa_100,

  CASE
    WHEN NVL(ex.sa_100_flag,0) = 1 THEN 'S.A 100%'
    WHEN NVL(ex.hb_50_flag,0)  = 1 THEN 'H.B 50%'
--    WHEN NVL(ex.fb_0_flag,0)   = 1 THEN 'F.B 0%'
    WHEN NVL(ex.bb_75_flag,0)  = 1 THEN 'B.B 75%'
    ELSE NULL
  END AS hotel_plan,

  a.total_allowance,
  a.meal,
  a.travel_expense,
  a.last_approval_date,
  a.status,
  a.task_ids,
a.approval_manager,
  CASE
    WHEN a.approval_manager = '1' THEN '✅تمت الموافقة'
    WHEN a.approval_manager = '0' THEN '❌تم الرفض'
    WHEN a.approval_manager = '2' OR a.approval_manager IS NULL THEN '⏳في انتظار الاعتماد'
    ELSE a.approval_manager
  END AS approval_manager_msg,
a.approval_car,
  CASE
    WHEN a.approval_car = '1' THEN '✅تمت الموافقة'
    WHEN a.approval_car = '2' THEN '❌تم الرفض'
    WHEN a.approval_car = '0' OR a.approval_car IS NULL THEN '⏳في انتظار الاعتماد'
    ELSE a.approval_car
  END AS approval_car_msg,
a.approval_hotel,
  CASE
    WHEN a.approval_hotel = '1' THEN '✅تمت الموافقة'
    WHEN a.approval_hotel = '2' THEN '❌تم الرفض'
    WHEN a.approval_hotel = '0' OR a.approval_hotel IS NULL THEN '⏳في انتظار الاعتماد'
    ELSE a.approval_hotel
  END AS approval_hotel_msg,

  CASE
    WHEN a.approval_finance = '1' THEN '✅تمت الموافقة'
    WHEN a.approval_finance = '2' THEN '❌تم الرفض'
    WHEN a.approval_finance = '0' OR a.approval_finance IS NULL THEN '⏳في انتظار الاعتماد'
    ELSE a.approval_finance

  END AS approval_finance_msg,

  a.Date_of_disbursement AS Date_of_disbursement,
  CAST(NULL AS VARCHAR2(4000)) AS attached_file,

  CASE
    WHEN NVL(a.delete_approval_car,0)     = 1
      OR NVL(a.delete_approval_hotel,0)   = 1
      OR NVL(a.delete_approval_finance,0) = 1
--    or NVL(a.approval_car,0)     = 0
--     or NVL(a.approval_hotel,0)   = 0
--     or NVL(a.approval_finance,0) = 0
    THEN '❌ مرفوض'
    WHEN NVL(a.approval_manager,0) = 1
     AND NVL(a.approval_car,0)     = 1
     AND NVL(a.approval_hotel,0)   = 1
     AND NVL(a.approval_finance,0) = 1
    THEN '✅ تم الصرف'
    ELSE '⏳ قيد المراجعة'
  END AS request_final_status,
a.APPROVAL_FINANCE,
  a.net_amount,
  a.DATE_OF_ADMINISTRATOR
FROM EPROMHQ.TRV_ALLOWANCE a
LEFT JOIN exp ex
       ON ex.request_id = a.request_id
LEFT JOIN CENTRAL.XXAPEX_HR_EMP_DATA h
       ON h.emp_number = a.emp_id
WHERE NVL(a.delete_approval_car,0)     <> 1
  AND NVL(a.delete_approval_hotel,0)   <> 1
  AND NVL(a.delete_approval_finance,0) <> 1
  AND a.request_type_id = '47'
      and a.request_id not in (select REQUEST_ID from EPROMHQ.TRV_ALLOWANCE_HOTELS);
