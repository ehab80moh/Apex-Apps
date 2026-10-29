
  CREATE OR REPLACE EDITIONABLE PACKAGE "EPROMHQ"."TRV_ALLOWANCE_PKG" AUTHID DEFINER AS
    c_req_type_external CONSTANT VARCHAR2(10) := '47';
    c_req_type_internal CONSTANT VARCHAR2(10) := '33';
    c_date_format       CONSTANT VARCHAR2(20) := 'YYYY-MM-DD';

    PROCEDURE init_page_defaults (
        p_app_user     IN VARCHAR2,
        p_tra_emp_num  IN OUT VARCHAR2,
        p_emp_number   OUT VARCHAR2,
        p_emp_id       OUT VARCHAR2
    );

    FUNCTION parse_date (
        p_date_str IN VARCHAR2
    ) RETURN DATE;

    FUNCTION validate_request (
        p_emp_id          IN VARCHAR2,
        p_request_type_id IN VARCHAR2,
        p_return_same_day IN VARCHAR2,
        p_date_from_str   IN VARCHAR2,
        p_date_to_str     IN VARCHAR2,
        p_lines_json      IN CLOB,
        p_hotels_json     IN CLOB,
        p_request_id      IN NUMBER DEFAULT NULL
    ) RETURN VARCHAR2;

    FUNCTION validate_dates (
        p_request_type_id IN VARCHAR2,
        p_return_same_day IN VARCHAR2,
        p_date_from_str   IN VARCHAR2,
        p_date_to_str     IN VARCHAR2
    ) RETURN VARCHAR2;

    FUNCTION validate_overlap (
        p_emp_id          IN VARCHAR2,
        p_request_type_id IN VARCHAR2,
        p_date_from       IN DATE,
        p_date_to         IN DATE,
        p_request_id      IN NUMBER DEFAULT NULL
    ) RETURN VARCHAR2;

    FUNCTION validate_hotel_nights (
        p_request_type_id IN VARCHAR2,
        p_return_same_day IN VARCHAR2,
        p_date_from       IN DATE,
        p_date_to         IN DATE,
        p_hotels_json     IN CLOB
    ) RETURN VARCHAR2;

    FUNCTION validate_hotels_json (
        p_request_type_id IN VARCHAR2,
        p_return_same_day IN VARCHAR2,
        p_hotels_json     IN CLOB
    ) RETURN VARCHAR2;

    FUNCTION validate_lines_json (
        p_lines_json IN CLOB
    ) RETURN VARCHAR2;

    PROCEDURE save_request (
        p_emp_id               IN VARCHAR2,
        p_request_type_id      IN VARCHAR2,
        p_return_same_day      IN VARCHAR2,
        p_trip_purpose         IN VARCHAR2,
        p_trip_location        IN VARCHAR2,
        p_trip_location_other  IN VARCHAR2,
        p_date_from_str        IN VARCHAR2,
        p_start_time           IN VARCHAR2,
        p_date_to_str          IN VARCHAR2,
        p_end_time             IN VARCHAR2,
        p_lines_json           IN CLOB,
        p_hotels_json          IN CLOB,
        p_file_names           IN VARCHAR2,
        p_task_ids             IN VARCHAR2,
        x_request_id           OUT NUMBER
    );

    PROCEDURE set_workflow_id (
        p_request_id  IN NUMBER,
        p_workflow_id IN VARCHAR2
    );

END trv_allowance_pkg;
/
