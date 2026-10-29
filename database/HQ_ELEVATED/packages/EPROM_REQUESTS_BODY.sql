
  CREATE OR REPLACE EDITIONABLE PACKAGE BODY "HQ_ELEVATED"."EPROM_REQUESTS" as

  function create_request_header
(
p_type_id number,
p_emp_no varchar2,
p_requester_emp_no varchar2
)
return number as
v_header_id number;
  begin
   INSERT INTO requests_headers (
    request_header_id,
    request_type_id,
    request_status,
    emp_no,
    requester_emp_no
) VALUES (
    null,
    p_type_id,
    10,
    p_emp_no,
    p_requester_emp_no
) returning request_header_id into v_header_id;
commit;
    return v_header_id;

  end create_request_header;
-----------------------------------------------------------------------------------------
  procedure change_request_status
(
p_request_header_id number,
p_status number
) as
  begin

    update requests_headers
    set request_status =p_status
    where request_header_id = p_request_header_id;

    commit;
  end change_request_status;

end eprom_requests;
/
