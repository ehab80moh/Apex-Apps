
  CREATE OR REPLACE EDITIONABLE PACKAGE BODY "HQ_ELEVATED"."ITR_REQUEST_ACTION_PKG" as
    c_app_id          constant number := 104;
    c_task_definition constant varchar2(255) := 'gen-wf-action';
    c_workflow        constant varchar2(255) := 'IT_REQUEST_WF';

    function actor_name(p_actor varchar2) return varchar2 is
    begin
        return trim(coalesce(p_actor, v('APP_USER'), sys_context('USERENV', 'SESSION_USER')));
    end actor_name;

    procedure assert_length(p_value varchar2, p_label varchar2, p_max number) is
    begin
        if length(p_value) > p_max then
            raise_application_error(-20212, p_label || ' exceeds ' || p_max || ' characters.');
        end if;
    end assert_length;

    function is_coordinator(p_actor varchar2) return boolean is
        l_count number;
    begin
        select count(*)
          into l_count
          from itr_team_members
         where username = p_actor
           and upper(role) = 'COORDINATOR';
        return l_count > 0;
    end is_coordinator;

    function is_team_member(p_actor varchar2, p_team_id number) return boolean is
        l_count number;
    begin
        select count(*)
          into l_count
          from itr_team_members
         where username = p_actor
           and team_id = p_team_id;
        return l_count > 0;
    end is_team_member;

    function is_team_leader(p_actor varchar2, p_team_id number) return boolean is
        l_count number;
    begin
        select count(*)
          into l_count
          from itr_team_members
         where username = p_actor
           and team_id = p_team_id
           and upper(role) in ('LEADER', 'COORDINATOR');
        return l_count > 0;
    end is_team_leader;

    function task_actor_allowed(
        p_task_id       number,
        p_request_id    number,
        p_expected_t_id varchar2,
        p_actor         varchar2
    ) return boolean is
        l_detail_pk   apex_tasks.detail_pk%type;
        l_state_code apex_tasks.state_code%type;
        l_owner      apex_tasks.actual_owner%type;
        l_t_id       apex_task_parameters.param_value%type;
        l_count      number;
    begin
        if p_task_id is null then
            return false;
        end if;

        select t.detail_pk,
               t.state_code,
               t.actual_owner,
               max(case when p.param_static_id = 'T_ID' then p.param_value end)
          into l_detail_pk, l_state_code, l_owner, l_t_id
          from apex_tasks t
          left join apex_task_parameters p
            on p.application_id = t.application_id
           and p.task_id = t.task_id
         where t.application_id = c_app_id
           and t.task_def_static_id = c_task_definition
           and t.task_id = p_task_id
           and t.state_code in ('UNASSIGNED', 'ASSIGNED')
         group by t.detail_pk, t.state_code, t.actual_owner;

        if l_detail_pk <> to_char(p_request_id) or l_t_id <> p_expected_t_id then
            return false;
        end if;

        if l_state_code = 'ASSIGNED' then
            return l_owner = p_actor;
        end if;

        select count(*)
          into l_count
          from apex_task_participants
         where application_id = c_app_id
           and task_id = p_task_id
           and participant = p_actor;

        return l_count > 0;
    exception
        when no_data_found then
            return false;
    end task_actor_allowed;

    procedure assert_task(
        p_task_id       number,
        p_request_id    number,
        p_expected_t_id varchar2,
        p_actor         varchar2
    ) is
        l_detail_pk   apex_tasks.detail_pk%type;
        l_state_code apex_tasks.state_code%type;
        l_owner      apex_tasks.actual_owner%type;
        l_t_id       apex_task_parameters.param_value%type;
        l_count      number;
    begin
        if p_task_id is null then
            raise_application_error(-20203, 'An active task is required for this action.');
        end if;

        begin
            select t.detail_pk,
                   t.state_code,
                   t.actual_owner,
                   max(case when p.param_static_id = 'T_ID' then p.param_value end)
              into l_detail_pk, l_state_code, l_owner, l_t_id
              from apex_tasks t
              left join apex_task_parameters p
                on p.application_id = t.application_id
               and p.task_id = t.task_id
             where t.application_id = c_app_id
               and t.task_def_static_id = c_task_definition
               and t.task_id = p_task_id
               and t.state_code in ('UNASSIGNED', 'ASSIGNED')
             group by t.detail_pk, t.state_code, t.actual_owner;
        exception
            when no_data_found then
                raise_application_error(-20204, 'The active task does not belong to this IT request.');
        end;

        if l_detail_pk <> to_char(p_request_id) then
            raise_application_error(-20204, 'The active task does not belong to this IT request.');
        end if;

        if l_t_id <> p_expected_t_id then
            raise_application_error(-20205, 'The active task is not valid for this IT request action.');
        end if;

        if l_state_code = 'ASSIGNED' then
            if l_owner <> p_actor then
                raise_application_error(-20213, 'The task is assigned to another user.');
            end if;
        else
            select count(*)
              into l_count
              from apex_task_participants
             where application_id = c_app_id
               and task_id = p_task_id
               and participant = p_actor;
            if l_count = 0 then
                raise_application_error(-20213, 'The user is not a participant in this task.');
            end if;
        end if;
    end assert_task;

    function active_workflow_id(p_request_id number) return number is
        l_workflow_id number;
    begin
        select workflow_id
          into l_workflow_id
          from (
                select workflow_id
                  from apex_workflows
                 where application_id = c_app_id
                   and workflow_def_static_id = c_workflow
                   and detail_pk = to_char(p_request_id)
                   and state_code = 'ACTIVE'
                 order by start_time desc
               )
         where rownum = 1;
        return l_workflow_id;
    exception
        when no_data_found then
            return null;
    end active_workflow_id;

    function can_perform(
        p_action     in varchar2,
        p_request_id in number,
        p_task_id    in number default null,
        p_actor      in varchar2 default null
    ) return boolean is
        l_actor       varchar2(255) := actor_name(p_actor);
        l_status      itr_requests.status%type;
        l_emp_id      itr_requests.emp_id%type;
        l_team_id     itr_requests.assigned_team_id%type;
        l_assigned_to itr_requests.assigned_to%type;
        l_action      varchar2(30) := upper(trim(p_action));
    begin
        select status, emp_id, assigned_team_id, assigned_to
          into l_status, l_emp_id, l_team_id, l_assigned_to
          from itr_requests
         where request_id = p_request_id;

        case l_action
            when c_assign_team then
                return l_status = 20
                   and is_coordinator(l_actor)
                   and task_actor_allowed(p_task_id, p_request_id, 'ITR_COORDINATOR_TRIAGE', l_actor);
            when c_complete_coordinator then
                return l_status = 20
                   and is_coordinator(l_actor)
                   and task_actor_allowed(p_task_id, p_request_id, 'ITR_COORDINATOR_TRIAGE', l_actor);
            when c_assign_member then
                return l_status = 100
                   and l_team_id is not null
                   and is_team_leader(l_actor, l_team_id)
                   and task_actor_allowed(p_task_id, p_request_id, 'ITR_TEAM_LEADER_ASSIGNMENT', l_actor);
            when c_claim then
                return l_status = 100
                   and l_team_id is not null
                   and l_assigned_to is null
                   and is_team_member(l_actor, l_team_id)
                   and task_actor_allowed(p_task_id, p_request_id, 'ITR_TECHNICIAN_WORK', l_actor);
            when c_finish then
                return l_status = 110
                   and l_team_id is not null
                   and l_assigned_to = l_actor
                   and is_team_member(l_actor, l_team_id)
                   and task_actor_allowed(p_task_id, p_request_id, 'ITR_TECHNICIAN_WORK', l_actor);
            when c_complete_requester then
                return l_status = 130
                   and l_emp_id = l_actor
                   and task_actor_allowed(p_task_id, p_request_id, 'ITR_USER_VERIFICATION', l_actor);
            when c_hold_requester then
                return l_status = 130
                   and l_emp_id = l_actor
                   and task_actor_allowed(p_task_id, p_request_id, 'ITR_USER_VERIFICATION', l_actor);
            when c_cancel then
                return l_status in (20, 100, 110)
                   and is_coordinator(l_actor)
                   and active_workflow_id(p_request_id) is not null;
            else
                return false;
        end case;
    exception
        when no_data_found then
            return false;
    end can_perform;

    procedure assert_coordinator(p_actor varchar2) is
    begin
        if not is_coordinator(p_actor) then
            raise_application_error(-20201, 'Only an IT coordinator can perform this action.');
        end if;
    end assert_coordinator;

    procedure assert_status(p_actual number, p_expected number) is
    begin
        if p_actual <> p_expected then
            raise_application_error(-20202, 'The IT request is no longer in the expected state.');
        end if;
    end assert_status;

    procedure merge_worker(p_worker varchar2, p_status number, p_request_id number) is
    begin
        merge into itr_request_workers target
        using (
            select p_worker worker_id, p_status status_id, p_request_id request_id
              from dual
        ) source
           on (target.worker_id = source.worker_id
           and target.status_id = source.status_id
           and target.request_id = source.request_id)
        when matched then
            update set target.start_date = sysdate
        when not matched then
            insert (worker_id, status_id, request_id, start_date)
            values (source.worker_id, source.status_id, source.request_id, sysdate);
    end merge_worker;

    procedure assign_team(
        p_request_id in number,
        p_task_id    in number,
        p_team_id    in number,
        p_it_note    in varchar2,
        p_actor      in varchar2 default null
    ) is
        l_actor        varchar2(255) := actor_name(p_actor);
        l_status       itr_requests.status%type;
        l_leader_count number;
    begin
        select status into l_status
          from itr_requests
         where request_id = p_request_id
         for update;
        assert_coordinator(l_actor);
        assert_status(l_status, 20);
        assert_task(p_task_id, p_request_id, 'ITR_COORDINATOR_TRIAGE', l_actor);
        assert_length(p_it_note, 'IT note', 500);

        if p_team_id is null then
            raise_application_error(-20210, 'A team must be selected.');
        end if;
        select count(*) into l_leader_count
          from itr_team_members
         where team_id = p_team_id
           and upper(role) in ('LEADER', 'COORDINATOR');
        if l_leader_count = 0 then
            raise_application_error(-20210, 'The selected team has no leader or coordinator.');
        end if;

        update itr_requests
           set assigned_team_id = p_team_id,
               assigned_to = null,
               status = 100,
               assigned_by = l_actor,
               assigned_date = sysdate,
               it_note = p_it_note
         where request_id = p_request_id
           and status = 20;
        if sql%rowcount <> 1 then
            raise_application_error(-20214, 'The IT request changed while it was being assigned.');
        end if;

        itr_team_queue_pkg.enqueue_request(p_request_id => p_request_id, p_team_id => p_team_id);
        apex_human_task.complete_task(p_task_id => p_task_id, p_autoclaim => true);
    exception
        when no_data_found then
            raise_application_error(-20215, 'IT request not found: ' || p_request_id);
    end assign_team;

    procedure complete_by_coordinator(
        p_request_id in number,
        p_task_id    in number,
        p_it_note    in varchar2,
        p_actor      in varchar2 default null
    ) is
        l_actor  varchar2(255) := actor_name(p_actor);
        l_status itr_requests.status%type;
    begin
        select status into l_status
          from itr_requests
         where request_id = p_request_id
         for update;
        assert_coordinator(l_actor);
        assert_status(l_status, 20);
        assert_task(p_task_id, p_request_id, 'ITR_COORDINATOR_TRIAGE', l_actor);
        assert_length(p_it_note, 'IT note', 500);

        update itr_requests
           set status = 150,
               sub_status = 'COMPLETED_BY_COORDINATOR',
               complete_date = sysdate,
               it_note = p_it_note
         where request_id = p_request_id
           and status = 20;
        if sql%rowcount <> 1 then
            raise_application_error(-20214, 'The IT request changed while it was being completed.');
        end if;

        apex_human_task.complete_task(p_task_id => p_task_id, p_autoclaim => true);
    exception
        when no_data_found then
            raise_application_error(-20215, 'IT request not found: ' || p_request_id);
    end complete_by_coordinator;

    procedure assign_member(
        p_request_id in number,
        p_task_id    in number,
        p_assignee   in varchar2,
        p_actor      in varchar2 default null
    ) is
        l_actor   varchar2(255) := actor_name(p_actor);
        l_status  itr_requests.status%type;
        l_team_id itr_requests.assigned_team_id%type;
    begin
        select status, assigned_team_id
          into l_status, l_team_id
          from itr_requests
         where request_id = p_request_id
         for update;
        assert_status(l_status, 100);
        if not is_team_leader(l_actor, l_team_id) then
            raise_application_error(-20201, 'Only the assigned team leader can assign this request.');
        end if;
        assert_task(p_task_id, p_request_id, 'ITR_TEAM_LEADER_ASSIGNMENT', l_actor);
        if p_assignee is null or not is_team_member(p_assignee, l_team_id) then
            raise_application_error(-20211, 'The assignee must belong to the assigned team.');
        end if;

        update itr_requests
           set assigned_to = p_assignee,
               status = 110,
               assigned_by = l_actor,
               assigned_date = sysdate
         where request_id = p_request_id
           and status = 100;
        if sql%rowcount <> 1 then
            raise_application_error(-20214, 'The IT request changed while the member was being assigned.');
        end if;

        itr_team_queue_pkg.assign_request_to_member(
            p_request_id => p_request_id,
            p_team_id    => l_team_id,
            p_username   => p_assignee
        );
        merge_worker(p_assignee, 2, p_request_id);
        apex_human_task.complete_task(p_task_id => p_task_id, p_autoclaim => true);
    exception
        when no_data_found then
            raise_application_error(-20215, 'IT request not found: ' || p_request_id);
    end assign_member;

    procedure claim_request(
        p_request_id in number,
        p_task_id    in number,
        p_actor      in varchar2 default null
    ) is
        l_actor       varchar2(255) := actor_name(p_actor);
        l_status      itr_requests.status%type;
        l_team_id     itr_requests.assigned_team_id%type;
        l_assigned_to itr_requests.assigned_to%type;
    begin
        select status, assigned_team_id, assigned_to
          into l_status, l_team_id, l_assigned_to
          from itr_requests
         where request_id = p_request_id
         for update;
        assert_status(l_status, 100);
        if l_assigned_to is not null or not is_team_member(l_actor, l_team_id) then
            raise_application_error(-20206, 'Only an unassigned member of the request team can claim it.');
        end if;
        assert_task(p_task_id, p_request_id, 'ITR_TECHNICIAN_WORK', l_actor);

        update itr_requests
           set assigned_to = l_actor,
               status = 110,
               received_by = l_actor,
               received_date = sysdate
         where request_id = p_request_id
           and status = 100
           and assigned_to is null;
        if sql%rowcount <> 1 then
            raise_application_error(-20214, 'The IT request was claimed by another user.');
        end if;

        itr_team_queue_pkg.assign_request_to_member(
            p_request_id => p_request_id,
            p_team_id    => l_team_id,
            p_username   => l_actor
        );
        merge_worker(l_actor, 3, p_request_id);
        apex_human_task.claim_task(p_task_id => p_task_id);
    exception
        when no_data_found then
            raise_application_error(-20215, 'IT request not found: ' || p_request_id);
    end claim_request;

    procedure finish_request(
        p_request_id   in number,
        p_task_id      in number,
        p_tech_comment in varchar2,
        p_actor        in varchar2 default null
    ) is
        l_actor       varchar2(255) := actor_name(p_actor);
        l_status      itr_requests.status%type;
        l_team_id     itr_requests.assigned_team_id%type;
        l_assigned_to itr_requests.assigned_to%type;
    begin
        select status, assigned_team_id, assigned_to
          into l_status, l_team_id, l_assigned_to
          from itr_requests
         where request_id = p_request_id
         for update;
        assert_status(l_status, 110);
        if l_assigned_to <> l_actor or not is_team_member(l_actor, l_team_id) then
            raise_application_error(-20206, 'Only the assigned technician can finish this request.');
        end if;
        assert_task(p_task_id, p_request_id, 'ITR_TECHNICIAN_WORK', l_actor);
        assert_length(p_tech_comment, 'Technician comment', 500);

        update itr_requests
           set status = 130,
               tech_comment = p_tech_comment
         where request_id = p_request_id
           and status = 110
           and assigned_to = l_actor;
        if sql%rowcount <> 1 then
            raise_application_error(-20214, 'The IT request changed while it was being finished.');
        end if;

        merge_worker(l_actor, 2, p_request_id);
        apex_human_task.complete_task(p_task_id => p_task_id, p_autoclaim => true);
    exception
        when no_data_found then
            raise_application_error(-20215, 'IT request not found: ' || p_request_id);
    end finish_request;

    procedure complete_by_requester(
        p_request_id   in number,
        p_task_id      in number,
        p_user_comment in varchar2,
        p_actor        in varchar2 default null
    ) is
        l_actor       varchar2(255) := actor_name(p_actor);
        l_status      itr_requests.status%type;
        l_emp_id      itr_requests.emp_id%type;
        l_assigned_to itr_requests.assigned_to%type;
    begin
        select status, emp_id, assigned_to
          into l_status, l_emp_id, l_assigned_to
          from itr_requests
         where request_id = p_request_id
         for update;
        assert_status(l_status, 130);
        if l_emp_id <> l_actor then
            raise_application_error(-20207, 'Only the requester can confirm completion.');
        end if;
        assert_task(p_task_id, p_request_id, 'ITR_USER_VERIFICATION', l_actor);
        assert_length(p_user_comment, 'User comment', 500);

        update itr_requests
           set status = 150,
               sub_status = 'COMPLETED_BY_USER',
               complete_date = sysdate,
               user_comment = p_user_comment
         where request_id = p_request_id
           and status = 130
           and emp_id = l_actor;
        if sql%rowcount <> 1 then
            raise_application_error(-20214, 'The IT request changed while completion was being confirmed.');
        end if;

        itr_team_queue_pkg.close_request(p_request_id => p_request_id, p_status => 'COMPLETED');
        if l_assigned_to is not null then
            merge_worker(l_assigned_to, 2, p_request_id);
        end if;
        apex_human_task.complete_task(p_task_id => p_task_id, p_autoclaim => true);
    exception
        when no_data_found then
            raise_application_error(-20215, 'IT request not found: ' || p_request_id);
    end complete_by_requester;

    procedure hold_by_requester(
        p_request_id   in number,
        p_task_id      in number,
        p_user_comment in varchar2,
        p_actor        in varchar2 default null
    ) is
        l_actor       varchar2(255) := actor_name(p_actor);
        l_status      itr_requests.status%type;
        l_emp_id      itr_requests.emp_id%type;
        l_assigned_to itr_requests.assigned_to%type;
    begin
        select status, emp_id, assigned_to
          into l_status, l_emp_id, l_assigned_to
          from itr_requests
         where request_id = p_request_id
         for update;
        assert_status(l_status, 130);
        if l_emp_id <> l_actor then
            raise_application_error(-20207, 'Only the requester can put this request on hold.');
        end if;
        assert_task(p_task_id, p_request_id, 'ITR_USER_VERIFICATION', l_actor);
        assert_length(p_user_comment, 'User comment', 500);

        update itr_requests
           set status = 120,
               user_comment = p_user_comment,
               assigned_to = null
         where request_id = p_request_id
           and status = 130
           and emp_id = l_actor;
        if sql%rowcount <> 1 then
            raise_application_error(-20214, 'The IT request changed while it was being put on hold.');
        end if;

        itr_team_queue_pkg.hold_request(p_request_id => p_request_id);
        if l_assigned_to is not null then
            merge_worker(l_assigned_to, 2, p_request_id);
        end if;
        apex_human_task.complete_task(p_task_id => p_task_id, p_autoclaim => true);
    exception
        when no_data_found then
            raise_application_error(-20215, 'IT request not found: ' || p_request_id);
    end hold_by_requester;

    procedure cancel_by_coordinator(
        p_request_id in number,
        p_task_id    in number,
        p_reason     in varchar2,
        p_actor      in varchar2 default null
    ) is
        l_actor        varchar2(255) := actor_name(p_actor);
        l_status       itr_requests.status%type;
        l_type_name    itr_request_types.name%type;
        l_it_note      itr_requests.it_note%type;
        l_workflow_id  number;
        l_sub_status   itr_requests.sub_status%type;
        l_cancel_note  itr_requests.it_note%type;
    begin
        select r.status, t.name, r.it_note
          into l_status, l_type_name, l_it_note
          from itr_requests r
          join itr_request_types t on t.id = r.request_type
         where r.request_id = p_request_id
         for update;

        assert_coordinator(l_actor);
        if l_status = 160 then
            return;
        end if;
        if l_status not in (20, 100, 110) then
            raise_application_error(-20202, 'This IT request can no longer be cancelled.');
        end if;
        if trim(p_reason) is null then
            raise_application_error(-20208, 'Cancellation reason is required.');
        end if;
        assert_length(trim(p_reason), 'Cancellation reason', 500);

        l_workflow_id := active_workflow_id(p_request_id);
        if l_workflow_id is null then
            raise_application_error(-20209, 'No active IT request workflow exists for cancellation.');
        end if;

        l_sub_status := substr(
            'CANCELLED_' || trim(both '_' from regexp_replace(upper(trim(l_type_name)), '[^A-Z0-9]+', '_')),
            1,
            50
        );
        l_cancel_note := substr(
            nvl(l_it_note, '')
            || case when l_it_note is null then '' else ' | ' end
            || 'Cancelled by ' || l_actor || ': ' || trim(p_reason),
            1,
            500
        );

        update itr_requests
           set status = 160,
               approved = 0,
               complete_date = sysdate,
               sub_status = l_sub_status,
               it_note = l_cancel_note
         where request_id = p_request_id
           and status in (20, 100, 110);
        if sql%rowcount <> 1 then
            raise_application_error(-20214, 'The IT request changed while it was being cancelled.');
        end if;

        itr_team_queue_pkg.close_request(p_request_id => p_request_id, p_status => 'CANCELLED');
        apex_workflow.terminate(p_instance_id => l_workflow_id);
    exception
        when no_data_found then
            raise_application_error(-20215, 'IT request not found: ' || p_request_id);
    end cancel_by_coordinator;
end itr_request_action_pkg;
/
