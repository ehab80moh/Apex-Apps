
  CREATE OR REPLACE EDITIONABLE PACKAGE "HQ_ELEVATED"."APPROVAL_PKG" IS
   -- Helper procedure
   PROCEDURE insert_approval (
       p_emp_number        IN NUMBER,
       p_request_type_id   IN NUMBER,
       p_approver          IN VARCHAR2,
       p_seq               IN NUMBER,
       p_is_mandatory      IN VARCHAR2,
       p_type              IN VARCHAR2,
       p_group_name        IN VARCHAR2,
       p_group_id          IN NUMBER,
       p_user              IN VARCHAR2
   );

   -- Main procedure
   PROCEDURE process_employee_requests (
       p_emp_numbers IN VARCHAR2,   -- e.g. '1392:1440:1550'
       p_site_code   IN NUMBER,
       p_approver1   IN NUMBER,
       p_approver2   IN NUMBER,
       p_fyi_list    IN VARCHAR2,   -- e.g. '200:201:202'
       p_app_user    IN VARCHAR2
   );

       PROCEDURE create_next_approval_log (
        p_request_id      IN NUMBER,
        p_request_source  IN VARCHAR2,
        p_request_type_id IN NUMBER,
        p_emp_id          IN NUMBER
    );
END approval_pkg;
/
