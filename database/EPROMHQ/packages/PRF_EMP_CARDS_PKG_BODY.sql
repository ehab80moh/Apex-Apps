
  CREATE OR REPLACE EDITIONABLE PACKAGE BODY "EPROMHQ"."PRF_EMP_CARDS_PKG" as
  procedure require_pr is
  begin
    if nvl(apex_application.g_flow_id,0)<>105 or nvl(v('APP_ID'),'0')<>'105' or v('APP_USER') is null
       or not regexp_like(v('APP_USER'),'^[0-9]+$') then
      raise_application_error(-20051,'Employee card access denied.');
    end if;
    if apex_authorization.is_authorized('Public Relations Department') then null; else
      raise_application_error(-20051,'Employee card access denied.');
    end if;
  end;

  function file_name(p_emp_id varchar2,p_slot number) return varchar2 is
    l_name varchar2(255);
  begin
    require_pr;
    if p_emp_id is null or not regexp_like(p_emp_id,'^[0-9]+$')
       or p_slot is null or p_slot not between 1 and 4 or p_slot<>trunc(p_slot) then
      raise_application_error(-20052,'The selected attachment is unavailable.');
    end if;
    select f.file_name into l_name from prf_emp_card_files_v f
     where f.emp_id=p_emp_id and f.slot_no=p_slot;
    if instr(l_name,'..')>0 or regexp_like(l_name,'[^[:alnum:]_. -]')
       or length(l_name)>255 then
      raise_application_error(-20052,'The selected attachment is unavailable.');
    end if;
    return l_name;
  exception when no_data_found then
    raise_application_error(-20052,'The selected attachment is unavailable.');
  end;

  function attachments_link(p_emp_id varchar2,p_count number) return varchar2 is
    l_url varchar2(4000);
  begin
    require_pr;
    if nvl(p_count,0)=0 then
      return '<span class="prf-no-files">لا توجد مرفقات</span>';
    end if;
    l_url:=apex_page.get_url(p_application=>'105',p_page=>'110',
      p_clear_cache=>'110',p_items=>'P110_EMP_ID',p_values=>p_emp_id);
    return '<a class="t-Button t-Button--small prf-files-button" style="border-color:#087d70;color:#087d70;border-radius:8px" href="'||
      apex_escape.html_attribute(l_url)||'" aria-label="'||
      apex_escape.html_attribute('عرض مرفقات الموظف '||p_emp_id)||'">'||
      '<span class="fa fa-paperclip" aria-hidden="true"></span> عرض المرفقات ('||
      to_char(p_count,'FM9990')||')</a>';
  end;

  function summary_html return clob is
    l_total number;
    l_complete number;
    l_partial number;
    l_none number;
    l_html clob;
    procedure card(p_value number,p_label varchar2,p_class varchar2) is
    begin
      l_html:=l_html||'<div class="prf-summary-card '||p_class||'"><strong>'||
        to_char(p_value,'FM999999990')||'</strong><span>'||p_label||'</span></div>';
    end;
  begin
    require_pr;
    select count(*),count(case when card_status='COMPLETE' then 1 end),
      count(case when card_status='INCOMPLETE' then 1 end),
      count(case when card_status='NONE' then 1 end)
      into l_total,l_complete,l_partial,l_none from prf_emp_cards_v;
    l_html:='<div class="prf-page-intro"><div><h2>بطاقات موظفي الشركة</h2>'||
      '<p>عرض ومراجعة بطاقات الموظفين ومرفقاتهم</p></div>'||
      '<span class="prf-permission">العلاقات العامة</span></div><div class="prf-summary">';
    card(l_total,'إجمالي الموظفين','is-total');
    card(l_complete,'بطاقات مكتملة','is-complete');
    card(l_partial,'بطاقات ناقصة','is-partial');
    card(l_none,'بدون مرفقات','is-none');
    return l_html||'</div>';
  end;

  function gallery_html(p_emp_id varchar2) return clob is
    l_emp prf_emp_cards_v%rowtype;
    l_html clob;
    l_url varchar2(4000);
    l_label varchar2(100);
  begin
    require_pr;
    select * into l_emp from prf_emp_cards_v where emp_id=p_emp_id;
    l_html:='<div class="prf-gallery-heading"><h2>بطاقات ومرفقات الموظف</h2><p>'||
      apex_escape.html(l_emp.employee_name)||' · '||apex_escape.html(l_emp.emp_id)||
      '</p><p>'||apex_escape.html(l_emp.department)||'</p></div>';
    if l_emp.attachment_count=0 then
      return l_html||'<p class="prf-empty">لا توجد مرفقات محفوظة لهذا الموظف.</p>';
    end if;
    l_html:=l_html||'<div class="prf-gallery">';
    for f in (select slot_no,file_name from prf_emp_card_files_v
               where emp_id=p_emp_id and person_id=l_emp.person_id order by slot_no) loop
      l_label:=case f.slot_no when 1 then 'وجه البطاقة' when 2 then 'ظهر البطاقة'
                  when 3 then 'مرفق إضافي 1' else 'مرفق إضافي 2' end;
      l_url:=apex_page.get_url(p_application=>'105',p_page=>'110',
        p_request=>'CARD_FILE',p_items=>'P110_EMP_ID,P110_SLOT',
        p_values=>p_emp_id||','||to_char(f.slot_no,'FM0'),p_plain_url=>true);
      l_html:=l_html||'<section class="prf-file-tile"><h3>'||l_label||'</h3>'||
        '<a target="_blank" rel="noopener noreferrer" href="'||
        apex_escape.html_attribute(l_url)||'" aria-label="'||
        apex_escape.html_attribute('تكبير '||l_label)||'">'||
        '<img class="prf-card-image" loading="lazy" decoding="async" src="'||
        apex_escape.html_attribute(l_url)||'" alt="'||l_label||'">'||
        '<span class="prf-image-error" hidden>تعذر عرض الملف. اضغط لفتحه.</span></a>'||
        '<a class="t-Button prf-files-button" target="_blank" rel="noopener noreferrer" href="'||
        apex_escape.html_attribute(l_url)||'">عرض وتكبير</a></section>';
    end loop;
    return l_html||'</div><p class="prf-gallery-footer">'||
      to_char(l_emp.attachment_count,'FM9990')||' مرفقات</p>';
  exception when no_data_found then
    return '<p class="prf-empty">لم يتم العثور على بيانات الموظف.</p>';
  end;

  procedure download_file(p_emp_id varchar2,p_slot number) is
    l_name varchar2(255);
    l_blob blob;
    l_header varchar2(32);
    l_mime varchar2(100);
    l_extension varchar2(8);
    l_disposition varchar2(20):='inline';
  begin
    l_name:=file_name(p_emp_id,p_slot);
    l_blob:=central.prf105_card_read(p_emp_id,p_slot);
    l_header:=rawtohex(dbms_lob.substr(l_blob,12,1));
    if substr(l_header,1,6)='FFD8FF' then l_mime:='image/jpeg'; l_extension:='.jpg';
    elsif substr(l_header,1,16)='89504E470D0A1A0A' then l_mime:='image/png'; l_extension:='.png';
    elsif substr(l_header,1,8)='25504446' then l_mime:='application/pdf'; l_extension:='.pdf';
    elsif substr(l_header,1,6)='474946' then l_mime:='image/gif'; l_extension:='.gif';
    elsif substr(l_header,1,4)='424D' then l_mime:='image/bmp'; l_extension:='.bmp';
    elsif substr(l_header,1,8)='52494646' and substr(l_header,17,8)='57454250' then l_mime:='image/webp'; l_extension:='.webp';
    else l_mime:='application/octet-stream'; l_extension:='.bin'; l_disposition:='attachment';
    end if;
    sys.htp.init;
    sys.owa_util.mime_header(l_mime,false);
    sys.htp.p('Content-Length: '||dbms_lob.getlength(l_blob));
    sys.htp.p('Content-Disposition: '||l_disposition||'; filename="employee-'||p_emp_id||'-'||to_char(p_slot,'FM0')||l_extension||'"');
    sys.htp.p('Cache-Control: private, no-store, max-age=0');
    sys.htp.p('Pragma: no-cache');
    sys.htp.p('X-Content-Type-Options: nosniff');
    sys.owa_util.http_header_close;
    sys.wpg_docload.download_file(l_blob);
    apex_application.stop_apex_engine;
  end;
end prf_emp_cards_pkg;
/
