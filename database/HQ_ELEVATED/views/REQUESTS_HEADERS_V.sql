
  CREATE OR REPLACE FORCE EDITIONABLE VIEW "HQ_ELEVATED"."REQUESTS_HEADERS_V" ("REQUEST_HEADER_ID", "REQUEST_TYPE_ID", "REQUEST_TYPE_NAME", "REQUEST_DISCRIPTION", "REQUEST_STATUS", "STATUS_NAME", "STATUS_DESCRIPTION", "EMP_NO", "REQUESTER_EMP_NO", "REJECT_REASON") AS
  select
h.request_header_id,
h.request_type_id,
rl.request_type_name,
rl.request_discription,
h.request_status,
s.status_name,
s.status_description,
h.emp_no,
h.requester_emp_no,
h.reject_reason
from
 requests_headers h
join CENTRAL.xxapex_ss_requests_list rl on rl.request_type_id = h.request_type_id
join CENTRAL.xxapex_ss_requests_status s on s.status_id = h.request_status;
