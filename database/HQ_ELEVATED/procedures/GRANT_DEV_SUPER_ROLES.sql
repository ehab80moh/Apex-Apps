
  CREATE OR REPLACE EDITIONABLE PROCEDURE "HQ_ELEVATED"."GRANT_DEV_SUPER_ROLES" (
    P_EMP_ID IN VARCHAR2
) AS
BEGIN
    -- Medical local accounts must never enter developer role or HR provisioning.
    FOR restricted_account IN (SELECT 1 FROM HQ_ELEVATED.DEVELOPERS_EMPS
       WHERE emp_id=P_EMP_ID AND ACCESS_PROFILE='MEDICAL_PORTAL') LOOP
      RAISE_APPLICATION_ERROR(-20872,'Medical portal accounts cannot receive developer provisioning');
    END LOOP;
    MERGE INTO CENTRAL.USER_ROLES_D_USER u
    USING (
        SELECT
            P_EMP_ID AS app_user,
            app_id, pages, role_id, role_name, role_type_id, auth_type
        FROM CENTRAL.USER_ROLES_D_USER
        WHERE app_user = '3199'
    ) s
    ON (u.app_user = s.app_user AND u.app_id = s.app_id AND u.role_id = s.role_id)
    WHEN NOT MATCHED THEN
        INSERT (app_user, app_id, pages, role_id, role_name, role_type_id, auth_type)
        VALUES (s.app_user, s.app_id, s.pages, s.role_id, s.role_name, s.role_type_id, s.auth_type);

    COMMIT;
END GRANT_DEV_SUPER_ROLES;
/
