
  CREATE OR REPLACE EDITIONABLE PACKAGE "HQ_ELEVATED"."ITR_REQUEST_ACTION_PKG" authid definer as
    c_assign_team          constant varchar2(30) := 'ASSIGN_TEAM';
    c_complete_coordinator constant varchar2(30) := 'COMPLETE_COORDINATOR';
    c_assign_member        constant varchar2(30) := 'ASSIGN_MEMBER';
    c_claim                constant varchar2(30) := 'CLAIM';
    c_finish               constant varchar2(30) := 'FINISH';
    c_complete_requester   constant varchar2(30) := 'COMPLETE_REQUESTER';
    c_hold_requester       constant varchar2(30) := 'HOLD_REQUESTER';
    c_cancel               constant varchar2(30) := 'CANCEL';

    function can_perform(
        p_action     in varchar2,
        p_request_id in number,
        p_task_id    in number   default null,
        p_actor      in varchar2 default null
    ) return boolean;

    procedure assign_team(
        p_request_id in number,
        p_task_id    in number,
        p_team_id    in number,
        p_it_note    in varchar2,
        p_actor      in varchar2 default null
    );

    procedure complete_by_coordinator(
        p_request_id in number,
        p_task_id    in number,
        p_it_note    in varchar2,
        p_actor      in varchar2 default null
    );

    procedure assign_member(
        p_request_id in number,
        p_task_id    in number,
        p_assignee   in varchar2,
        p_actor      in varchar2 default null
    );

    procedure claim_request(
        p_request_id in number,
        p_task_id    in number,
        p_actor      in varchar2 default null
    );

    procedure finish_request(
        p_request_id  in number,
        p_task_id     in number,
        p_tech_comment in varchar2,
        p_actor       in varchar2 default null
    );

    procedure complete_by_requester(
        p_request_id  in number,
        p_task_id     in number,
        p_user_comment in varchar2,
        p_actor       in varchar2 default null
    );

    procedure hold_by_requester(
        p_request_id  in number,
        p_task_id     in number,
        p_user_comment in varchar2,
        p_actor       in varchar2 default null
    );

    procedure cancel_by_coordinator(
        p_request_id in number,
        p_task_id    in number,
        p_reason     in varchar2,
        p_actor      in varchar2 default null
    );
end itr_request_action_pkg;
/
