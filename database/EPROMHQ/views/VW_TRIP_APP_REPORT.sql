
  CREATE OR REPLACE FORCE EDITIONABLE VIEW "EPROMHQ"."VW_TRIP_APP_REPORT" ("APP_ID", "EMP_ID", "EMP_NAME", "TRIP_ID", "LAST_BENEFIT", "APPLICATION_STATUS", "LOCATION_ID", "CREATED_BY", "CREATED_AT", "COMPANIONS_DETAILS", "COMPANIONS_COUNT", "ROOMS_DETAILS", "TOTAL_ROOMS") AS
  SELECT
    a.app_id,
    a.emp_id,
        a.emp_id as emp_name,
    a.trip_id,
--    a.transportation_type,
    nvl(a.emp_last_benefit,'لايوجد استفادات سابقة')  as last_benefit,
    a.application_status,
    a.location_id,
--    a.is_apology,
--    a.update_for_apology,
    a.created_by,
    a.created_at,

    /* ====== الأقارب/المرافقين ====== */
    ( SELECT LISTAGG(
               c.person_name
               || NVL2(c.person_relation, ' (' || c.person_relation || ')', '')
               || NVL2(c.person_birthdate, ' - ' || TO_CHAR(c.person_birthdate,'DD-MM-YYYY'), '')
               , ' | '
           ) WITHIN GROUP (ORDER BY c.companion_id)
--           ON OVERFLOW TRUNCATE ' ...'
      FROM EPROMHQ.trip_companions c
      WHERE c.app_id = a.app_id
    ) AS companions_details,

    ( SELECT COUNT(*)
      FROM EPROMHQ.trip_companions c
      WHERE c.app_id = a.app_id
    ) AS companions_count,

    /* ====== الفنادق/الغرف ====== */
    ( SELECT LISTAGG(
               r.room_type || ': ' || r.num_of_rooms
               , ' | '
           ) WITHIN GROUP (ORDER BY r.room_type)
--           ON OVERFLOW TRUNCATE ' ...'
      FROM EPROMHQ.trip_rooms r
      WHERE r.app_id = a.app_id
    ) AS rooms_details,

    ( SELECT NVL(SUM(r.num_of_rooms),0)
      FROM EPROMHQ.trip_rooms r
      WHERE r.app_id = a.app_id
    ) AS total_rooms

FROM EPROMHQ.trip_applications a
where a.application_status = 'D'
and (is_apology is null or is_apology <> 1);
