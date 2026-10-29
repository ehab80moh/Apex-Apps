
  CREATE OR REPLACE EDITIONABLE PACKAGE "EPROMHQ"."TMS_API" AS
------------------------------------------------------------------- VACATIONS---------------------------------------------------
procedure upload_tms_vacations;
procedure DELETE_tms_vacations;

procedure cut_weekends_and_insert_vacations
/*
This procedure is called from the upload_tms_vacations procedure.
It processes each day within a specified date range,
checks if the day is not a weekend or a holiday,
and then cuts and inserts vacations accordingly
*/
(
 p_from       DATE,
        p_to         DATE,
        p_leave_type VARCHAR2,
        p_emp_id     VARCHAR2,
        p_request_id NUMBER
);

procedure insert_tms_vacation
/* This procedure is also called from the upload_tms_vacations procedure.
It inserts TMS vacations by making a REST request to an external system to create a new vacation entry.
It then updates the hrf_emp_leave_request table with the TMS ID and logs the request response */
(
p_from date
,p_to date
,p_leave_type VARCHAR2
,p_emp_id VARCHAR2
,p_request_id number
);

procedure delete_tms_vacation
/*
This procedure appears to delete TMS vacations.
It selects records from the hrf_emp_leave_request table
with specific conditions and then processes the TMS vacation IDs to delete them.
This is likely used for managing or canceling employee leave requests in the external system
*/
(
p_tms_id number
,p_request_id number
);
-------------------------------------------------------------------END VACATIONS---------------------------------------------------
-------------------------------------------------------------------MISSIONS---------------------------------------------------
procedure upload_tms_MISSIONS;
procedure DELETE_tms_MISSIONS;

 PROCEDURE cut_weekends_and_insert_missions
 /*
 This procedure is called from upload_tms_MISSIONS and is responsible for processing mission data.
 It appears to iterate through a date range, checking if specific days are weekends,
 and inserting mission data based on certain conditions.
 The p_type parameter suggests that different types of missions might be handled differently.
 */
 (
    p_from        DATE,
        p_to          DATE,
        p_description VARCHAR2,
        p_emp_id      VARCHAR2,
        p_request_id  NUMBER,
        p_type        VARCHAR2
    );

procedure insert_tms_MISSION
/*
This procedure seems to be responsible for inserting mission-related data into a database.
It takes various parameters such as start and end dates, a description, employee ID,
request ID, and a mission type. The mission data is inserted into the database
*/
(
p_from date
,p_to date
,p_Description VARCHAR2
,p_emp_id VARCHAR2
,p_request_id number
,p_type varchar2
);

procedure delete_tms_MISSION
/*
This procedure likely handles the deletion of mission-related data.
It might select and process records from a table with specific conditions,
such as records that need to be deleted. The details of what records
are being deleted would depend on the specific implementation.
*/
(
p_tms_id number
,p_request_id number
,p_type        VARCHAR2
);


-------------------------------------------------------------------END MISSIONS---------------------------------------------------
-------------------------------------------------------------------PERMISSIONS---------------------------------------------------
procedure upload_tms_PERMISSIONS;
procedure DELETE_tms_PERMISSIONS;

procedure insert_tms_PERMISSION(
p_date date,
p_from date
,p_to date
,p_CODE VARCHAR2
,p_desc VARCHAR2
,p_emp_id VARCHAR2
,p_request_id number
);

procedure delete_tms_PERMISSION(
p_tms_id number
,p_request_id number
);

-------------------------------------------------------------------END PERMISSIONS---------------------------------------------------
-------------------------------------------------------------------OVERTIME---------------------------------------------------
procedure upload_tms_OVERTIMES;
procedure DELETE_tms_OVERTIMES;

procedure insert_tms_OVERTIME(
p_date date,
p_from date
,p_to date
,p_emp_id VARCHAR2
,p_request_id number
,p_desc varchar2
);

procedure delete_tms_OVERTIME(
p_tms_id number
,p_request_id number
);

-------------------------------------------------------------------END OVERTIME---------------------------------------------------

-------------------------------------------------------------------OTHER FUNCTIONS ---------------------------------------------------
FUNCTION in_holiday (p_date Date) RETURN BOOLEAN;

FUNCTION get_cut_date (p_date Date,p_location varchar) RETURN date;

-------------------------------------------------------------------END OTHER FUNCTIONS ---------------------------------------------------
END TMS_API;
/
