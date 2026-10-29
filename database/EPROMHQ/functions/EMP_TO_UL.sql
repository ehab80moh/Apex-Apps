
  CREATE OR REPLACE EDITIONABLE FUNCTION "EPROMHQ"."EMP_TO_UL" (
p_emp_list IN VARCHAR2
,p_seperator varchar2 default ':'
,p_show_names varchar2 DEFAULT 'N' --Y
,p_leaders varchar2 DEFAULT 'N' --Y
,p_all_leaders varchar2 DEFAULT 'N' --Y
)
RETURN VARCHAR2
IS
  v_emp_array APEX_APPLICATION_GLOBAL.VC_ARR2;
  v_html VARCHAR2(32767);
  CURSOR c_emps (c_emp_list varchar2,c_seperator varchar2)
  is
  select emp_number||' - '|| emp_name name_id ,emp_number emp_id
  from CENTRAL.xxapex_hr_emp_data
where emp_number in (
select column_value from table(
 apex_string.split(c_emp_list,c_seperator)
)
)
;
v_li_cls VARCHAR2(50);
BEGIN
--check if the list is all leaders
 if p_all_leaders='Y' then
 v_li_cls :='leader';
 else
 v_li_cls:='';
 end if;

  -- Generate the unordered list HTML.
 v_html := '<ul class="team">';

 if p_show_names='Y' then

for c in c_emps(p_emp_list,p_seperator) loop
if p_leaders is not null and search_delimeted_string(p_string=>p_leaders,p_search=>c.emp_id) =1 then
 v_html := v_html || '<li class="leader">' || c.name_id || '</li>';
else
  v_html := v_html || '<li class="'||v_li_cls||'">' || c.name_id || '</li>';
  end if;
end loop;

 else
  -- Split the input string into an array.
  v_emp_array := apex_util.string_to_table(p_emp_list, p_seperator);
  FOR i IN 1..v_emp_array.COUNT LOOP
    v_html := v_html || '<li>' || v_emp_array(i) || '</li>';
  END LOOP;

end if;
  v_html := v_html || '</ul>';
  -- Return the HTML string.
  RETURN v_html;
END;
/
