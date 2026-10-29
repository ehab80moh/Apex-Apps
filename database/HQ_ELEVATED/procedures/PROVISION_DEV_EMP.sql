
  CREATE OR REPLACE EDITIONABLE PROCEDURE "HQ_ELEVATED"."PROVISION_DEV_EMP" (
    P_EMP_ID    IN VARCHAR2,
    P_EMP_NAME  IN VARCHAR2,
    P_PHONE     IN VARCHAR2,
    P_PASSWORD  IN VARCHAR2 DEFAULT 'Dev@123456',
    P_EMAIL     IN VARCHAR2 DEFAULT NULL
) AS
BEGIN
    -- Medical local accounts must never enter developer role or HR provisioning.
    FOR restricted_account IN (SELECT 1 FROM HQ_ELEVATED.DEVELOPERS_EMPS
       WHERE emp_id=P_EMP_ID AND ACCESS_PROFILE='MEDICAL_PORTAL') LOOP
      RAISE_APPLICATION_ERROR(-20872,'Medical portal accounts cannot receive developer provisioning');
    END LOOP;
    -- 1. Upsert into HQ_ELEVATED.DEVELOPERS_EMPS
    MERGE INTO HQ_ELEVATED.DEVELOPERS_EMPS d
    USING (SELECT P_EMP_ID AS emp_id FROM dual) s
    ON (d.emp_id = s.emp_id)
    WHEN MATCHED THEN
        UPDATE SET
            emp_name = P_EMP_NAME,
            phone = P_PHONE,
            email = P_EMAIL,
            is_active = 'Y'
    WHEN NOT MATCHED THEN
        INSERT (emp_id, emp_name, phone, email, site_code, project, emp_position_name, is_active)
        VALUES (P_EMP_ID, P_EMP_NAME, P_PHONE, P_EMAIL, 'EPROM_HQ_ALEX', 'المركز الرئيسي', 'مهندس أول', 'Y');

    -- 2. Upsert into CENTRAL.EMP_CONTACT (for OTP mobile lookup)
    MERGE INTO CENTRAL.EMP_CONTACT c
    USING (SELECT P_EMP_ID AS emp_id FROM dual) s
    ON (c.emp_id = s.emp_id)
    WHEN MATCHED THEN
        UPDATE SET
            mobile = P_PHONE,
            mobile_confirmed = 1
    WHEN NOT MATCHED THEN
        INSERT (emp_id, mobile, mobile_confirmed)
        VALUES (P_EMP_ID, P_PHONE, 1);

    -- 3. Upsert into CENTRAL.EMP_CRIDS (triggers EMP_CRIDS_INSERT / EMP_CRIDS_UPDATE hash the password automatically)
    MERGE INTO CENTRAL.EMP_CRIDS r
    USING (SELECT P_EMP_ID AS emp_id FROM dual) s
    ON (r.emp_id = s.emp_id)
    WHEN MATCHED THEN
        UPDATE SET
            pass = P_PASSWORD,
            password_changed = 'Y'
    WHEN NOT MATCHED THEN
        INSERT (emp_id, pass, password_changed)
        VALUES (P_EMP_ID, P_PASSWORD, 'Y');

    -- 4. Upsert into CENTRAL.XXAPEX_HR_EMP_DATA
    MERGE INTO CENTRAL.XXAPEX_HR_EMP_DATA h
    USING (SELECT P_EMP_ID AS emp_number FROM dual) s
    ON (h.emp_number = s.emp_number)
    WHEN MATCHED THEN
        UPDATE SET
            emp_name = P_EMP_NAME,
            site_code = 'EPROM_HQ_ALEX',
            project = 'المركز الرئيسي',
            organization_name = 'المركز الرئيسي',
            emp_position_name = 'مهندس أول',
            comp_email = P_EMAIL,
            pay_email = P_EMAIL,
            egpc_email = P_EMAIL
    WHEN NOT MATCHED THEN
        INSERT (emp_number, emp_name, national_identifier, emp_date_of_birth, emp_position_name, site_code, organization_name, assignments_date, grade_name, permanent_date, excel_pos, project, basic_salary, exp_date, image, image_id, comp_email, pay_email, egpc_email, mar_stat, job_date, prim_address)
        VALUES (P_EMP_ID, P_EMP_NAME, '29000000000000', TO_CHAR(SYSDATE, 'DD/MM/YYYY'), 'مهندس أول', 'EPROM_HQ_ALEX', 'المركز الرئيسي', TO_CHAR(SYSDATE, 'DD/MM/YYYY'), 'EPROM.10', TO_CHAR(SYSDATE, 'DD/MM/YYYY'), 'Senior Engineer', 'المركز الرئيسي', 0, TO_CHAR(SYSDATE, 'DD/MM/YYYY'), TO_BLOB(NULL), NULL, P_EMAIL, P_EMAIL, P_EMAIL, 'Single', SYSDATE, 'Alexandria');

    -- 5. Seed all application super_duper & admin roles from 3199 into CENTRAL.USER_ROLES_D_USER
    GRANT_DEV_SUPER_ROLES(P_EMP_ID);

    COMMIT;
END PROVISION_DEV_EMP;
/
