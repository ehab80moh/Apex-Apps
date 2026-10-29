
  CREATE OR REPLACE EDITIONABLE PACKAGE "HQ_ELEVATED"."EPROM_REQUESTS" as


function create_request_header
(
p_TYPE_ID number,
p_EMP_NO varchar2,
p_REQUESTER_EMP_NO varchar2
)
return number;

procedure change_request_status
(
p_request_header_id number,
p_status number
);


end eprom_requests;
/
