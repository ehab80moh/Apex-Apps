
  CREATE OR REPLACE EDITIONABLE PACKAGE "HQ_ELEVATED"."AI_AGENT_REQUESTS_PKG" AS
    /**
     * Package: AI_AGENT_REQUESTS_PKG
     * Schema: HQ_ELEVATED
     * Purpose: Provides programmatic functions to simulate leaving, permission, and mission requests
     *          originating from APEX Application 115 (HR Forms). It executes validations via central.xxapex_ss_validations,
     *          inserts records into EPROMHQ tables, registers human tasks, and publishes status back to
     *          the APEX AI Agent loop using APEX_AI.SET_TOOL_RESULT.
     */

    /**
     * Function: GET_USER_LANG
     * Purpose: Retrieves the user's active language preference from the APEX session.
     * Returns: VARCHAR2 ('ar-ae' for Arabic, or 'en-us' for English)
     */
    FUNCTION get_user_lang RETURN VARCHAR2;

    /**
     * Function: GET_SESSION_INFO
     * Purpose: Retrieves active session metadata and returns it as a formatted JSON string.
     * Returns: VARCHAR2 (JSON containing session_language, employee_id, employee_name, employee_project, employee_site, and mobile)
     */
    FUNCTION get_session_info RETURN VARCHAR2;

    /**
     * Function: CREATE_LEAVE_REQUEST
     * Purpose: Programmatically creates a Leave Request.
     * Parameters:
     *   - p_emp_id: Employee ID making the request
     *   - p_leave_type: Leave type code (e.g. 'C' for casual, 'H' for annual)
     *   - p_from_date: Start date of leave in 'YYYY-MM-DD' format
     *   - p_to_date: End date of leave in 'YYYY-MM-DD' format
     *   - p_cover_person: (Optional) Employee ID of the cover person
     * Returns: VARCHAR2 (Status message in Arabic or English)
     */
    FUNCTION create_leave_request (
        p_emp_id                 IN  VARCHAR2,
        p_leave_type             IN  VARCHAR2,
        p_from_date              IN  VARCHAR2, -- Format: YYYY-MM-DD
        p_to_date                IN  VARCHAR2, -- Format: YYYY-MM-DD
        p_cover_person           IN  VARCHAR2 DEFAULT NULL
    ) RETURN VARCHAR2;

    /**
     * Function: CREATE_PERMISSION_REQUEST
     * Purpose: Programmatically creates a Personal or Company Permission Request.
     * Parameters:
     *   - p_emp_id: Employee ID making the request
     *   - p_permission_type: 'PP' (Personal) or 'CP' (Company)
     *   - p_reason: Reason description for the permission
     *   - p_permission_date: Date of permission in 'YYYY-MM-DD' format
     *   - p_from_hour: Start time of permission in 'HH24:MI' format
     *   - p_to_hour: End time of permission in 'HH24:MI' format
     * Returns: VARCHAR2 (Status message in Arabic or English)
     */
    FUNCTION create_permission_request (
        p_emp_id                 IN  VARCHAR2,
        p_permission_type        IN  VARCHAR2, -- 'PP' or 'CP'
        p_reason                 IN  VARCHAR2,
        p_permission_date        IN  VARCHAR2, -- Format: YYYY-MM-DD
        p_from_hour              IN  VARCHAR2, -- Format: HH24:MI
        p_to_hour                IN  VARCHAR2  -- Format: HH24:MI
    ) RETURN VARCHAR2;

    /**
     * Function: CREATE_MISSION_REQUEST
     * Purpose: Programmatically creates a Mission Request.
     * Parameters:
     *   - p_emp_id: Employee ID making the request
     *   - p_from_date: Start date of mission in 'YYYY-MM-DD' format
     *   - p_to_date: End date of mission in 'YYYY-MM-DD' format
     *   - p_request_type_id: 72 (Standard Mission) or 121 (Training Mission)
     *   - p_description: Detailed description of the mission
     * Returns: VARCHAR2 (Status message in Arabic or English)
     */
    FUNCTION create_mission_request (
        p_emp_id                 IN  VARCHAR2,
        p_from_date              IN  VARCHAR2, -- Format: YYYY-MM-DD
        p_to_date                IN  VARCHAR2, -- Format: YYYY-MM-DD
        p_request_type_id        IN  NUMBER,   -- 72 or 121
        p_description            IN  VARCHAR2
    ) RETURN VARCHAR2;
END ai_agent_requests_pkg;
/
