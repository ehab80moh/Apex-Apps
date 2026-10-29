
  CREATE OR REPLACE EDITIONABLE PACKAGE BODY "EPROMHQ"."SPORTS_DAY_PKG" as
  c_event constant varchar2(30) := 'SPORTS_DAY_2026';

  procedure current_employee(p_emp out varchar2, p_person out number) is
  begin
    p_emp := v('APP_USER');
    if nvl(v('APP_ID'), '0') <> '104'
       or p_emp is null
       or p_emp not in ('3199','995','1837','3775') then
      raise_application_error(-20001, 'هذا النموذج غير متاح للمستخدم الحالي.');
    end if;
    select person_id into p_person
      from central.xxapex_hr_emp_data where emp_number = p_emp;
  exception
    when no_data_found then
      raise_application_error(-20002, 'تعذر تحديد بيانات الموظف الحالي.');
  end;

  function normalize_games(p_games varchar2) return varchar2 is
    l_tokens apex_t_varchar2;
    l_result varchar2(200);
    l_order apex_t_varchar2 := apex_string.split(
      'FOOTBALL:TABLE_TENNIS:BEACH_BALL:RUN_100M:TUG_OF_WAR', ':');
    l_seen varchar2(200) := ':';
  begin
    if p_games is null or length(p_games) > 200
       or substr(p_games,1,1) = ':' or substr(p_games,-1) = ':'
       or instr(p_games,'::') > 0 then
      raise_application_error(-20003, 'اختر لعبة واحدة على الأقل من القائمة.');
    end if;
    l_tokens := apex_string.split(p_games, ':');
    for i in 1 .. l_tokens.count loop
      if l_tokens(i) is null or l_tokens(i) not in
        ('FOOTBALL','TABLE_TENNIS','BEACH_BALL','RUN_100M','TUG_OF_WAR')
        or instr(l_seen, ':' || l_tokens(i) || ':') > 0 then
        raise_application_error(-20003, 'اختيارات الألعاب غير صحيحة.');
      end if;
      l_seen := l_seen || l_tokens(i) || ':';
    end loop;
    -- Store a canonical order, independently of the browser's submitted order.
    for i in 1 .. l_order.count loop
      if instr(l_seen, ':' || l_order(i) || ':') > 0 then
        if l_result is not null then l_result := l_result || ':'; end if;
        l_result := l_result || l_order(i);
      end if;
    end loop;
    return l_result;
  end;

  function has_card_side(p_side number) return boolean is
    l_emp varchar2(30);
    l_person number;
    l_count number;
  begin
    current_employee(l_emp, l_person);
    if p_side not in (1,2) or p_side is null then return false; end if;
    select count(*) into l_count from hrf_person_attachments
     where emp_id = l_emp and person_id = l_person
       and ((p_side = 1 and attach1 is not null)
         or (p_side = 2 and attach2 is not null));
    return l_count > 0;
  end;

  function card_complete return boolean is
    l_emp varchar2(30);
    l_person number;
    l_count number;
  begin
    current_employee(l_emp,l_person);
    select count(*) into l_count from hrf_person_attachments
     where emp_id=l_emp and person_id=l_person
       and attach1 is not null and attach2 is not null;
    return l_count > 0;
  end;

  function saved_games return varchar2 is
    l_emp varchar2(30);
    l_person number;
    l_games varchar2(200);
  begin
    current_employee(l_emp, l_person);
    select games into l_games from sports_day_registrations
     where event_code = c_event and emp_id = l_emp and status='ACTIVE';
    return l_games;
  exception when no_data_found then return null;
  end;

  function is_registered return boolean is
    l_emp varchar2(30);
    l_person number;
    l_count number;
  begin
    current_employee(l_emp,l_person);
    select count(*) into l_count from sports_day_registrations
     where event_code=c_event and emp_id=l_emp and status='ACTIVE';
    return l_count>0;
  end;

  function registration_html return clob is
    l_emp varchar2(30);
    l_person number;
    l_status varchar2(12);
  begin
    current_employee(l_emp,l_person);
    select status into l_status from sports_day_registrations
     where event_code=c_event and emp_id=l_emp;
    if l_status='ACTIVE' then
      return '<div class="sports-note sports-ok" role="status">اشتراكك مؤكد. يمكنك تعديل الألعاب وحفظها، أو إلغاء الاشتراك من الزر أسفل النموذج.</div>';
    end if;
    return '<div class="sports-note" role="status">تم إلغاء اشتراكك. يمكنك اختيار الألعاب وحفظ الاشتراك للتقديم مرة أخرى؛ صور البطاقة المحفوظة لا تحتاج إلى إعادة رفع.</div>';
  exception when no_data_found then
    return '<div class="sports-note" role="status">للاشتراك: اختر لعبة أو أكثر، وتأكد من اكتمال صور البطاقة، ثم اضغط حفظ الاشتراك.</div>';
  end;

  procedure cancel_registration is
    l_emp varchar2(30);
    l_person number;
  begin
    current_employee(l_emp,l_person);
    update sports_day_registrations
       set status='CANCELLED',cancelled_at=systimestamp,updated_at=systimestamp
     where event_code=c_event and emp_id=l_emp and status='ACTIVE';
    -- Idempotent cancellation, own row only; preserve choices, cards and history.
    -- No COMMIT: the APEX request owns the transaction.
  end;

  function card_html return clob is
    l_emp varchar2(30);
    l_person number;
    l_front varchar2(4000);
    l_back varchar2(4000);
    l_link varchar2(4000);
    l_result clob;
    function thumbnail(p_file varchar2, p_caption varchar2, p_side number) return varchar2 is
      l_image_url varchar2(4000);
    begin
      if p_file is null then return null; end if;
      l_image_url := apex_page.get_url(p_page=>'115',
        p_request=>case p_side when 1 then 'SPORTS_CARD_FRONT' else 'SPORTS_CARD_BACK' end,
        p_plain_url=>true);
      return '<a class="sports-id-thumb" target="_top" href="'
        || apex_escape.html_attribute(l_link) || '"><img src="'
        || apex_escape.html_attribute(l_image_url) || '" alt="'
        || apex_escape.html_attribute(p_caption) || '"><span>'
        || apex_escape.html(p_caption) || ' · محفوظة</span></a>';
    end;
  begin
    current_employee(l_emp, l_person);
    begin
      select attach1, attach2 into l_front, l_back
        from hrf_person_attachments where emp_id=l_emp and person_id=l_person;
    exception when no_data_found then null;
    end;
    l_link := apex_page.get_url(p_application=>'115',p_page=>'9',p_plain_url=>true);
    if l_front is not null and l_back is not null then
      l_result := '<p class="sports-note sports-ok" role="status"><span class="fa fa-check-circle" aria-hidden="true"></span> تم رفع صورة بطاقتك مسبقا</p>';
    elsif l_front is not null then
      l_result := '<p class="sports-note" role="status">وجه البطاقة محفوظ بالفعل. ارفع ظهر البطاقة فقط لاستكمال الاشتراك.</p>';
    elsif l_back is not null then
      l_result := '<p class="sports-note" role="status">ظهر البطاقة محفوظ بالفعل. ارفع وجه البطاقة فقط لاستكمال الاشتراك.</p>';
    else
      l_result := '<p class="sports-note" role="status">ارفع وجه بطاقة الرقم القومي وظهرها مرة واحدة، ثم أكمل اشتراكك.</p>';
    end if;
    return l_result || '<div class="sports-id-grid">'
      || thumbnail(l_front,'وجه البطاقة',1) || thumbnail(l_back,'ظهر البطاقة',2) || '</div>';
  end;

  procedure download_card(p_side number) is
    l_emp varchar2(30);
    l_person number;
    l_filename varchar2(4000);
    l_blob blob;
    l_header varchar2(16);
    l_mime varchar2(50);
  begin
    current_employee(l_emp,l_person);
    if p_side is null or p_side not in (1,2) then
      raise_application_error(-20004,'Invalid card side.');
    end if;
    select case p_side when 1 then attach1 else attach2 end into l_filename
      from hrf_person_attachments where emp_id=l_emp and person_id=l_person;
    if l_filename is null then raise_application_error(-20015,'Saved card side is unavailable.'); end if;
    l_blob := central.sports_card_read(l_filename);
    l_header := rawtohex(dbms_lob.substr(l_blob,8,1));
    if l_header='89504E470D0A1A0A' then l_mime:='image/png';
    elsif substr(l_header,1,6)='FFD8FF' then l_mime:='image/jpeg';
    else raise_application_error(-20015,'Saved card image format is invalid.');
    end if;
    sys.htp.init;
    sys.owa_util.mime_header(l_mime,false);
    sys.htp.p('Content-Length: ' || dbms_lob.getlength(l_blob));
    sys.htp.p('Cache-Control: private, no-store, max-age=0');
    sys.htp.p('X-Content-Type-Options: nosniff');
    sys.owa_util.http_header_close;
    sys.wpg_docload.download_file(l_blob);
    apex_application.stop_apex_engine;
  end;


  procedure load_image(p_name varchar2, p_blob out blob, p_extension out varchar2) is
    l_mime varchar2(255);
    l_header varchar2(16);
  begin
    if p_name is null or instr(p_name,':') > 0 then
      raise_application_error(-20004, 'ارفع صورة واضحة لكل جانب غير موجود من البطاقة.');
    end if;
    -- APEX's view scopes files to the current session; also enforce application.
    select blob_content, lower(mime_type) into p_blob, l_mime
      from apex_application_temp_files
     where name=p_name and application_id=104;
    if nvl(dbms_lob.getlength(p_blob),0)=0 or dbms_lob.getlength(p_blob)>5242880 then
      raise_application_error(-20005, 'حجم كل صورة يجب ألا يتجاوز 5 ميجابايت.');
    end if;
    l_header := rawtohex(dbms_lob.substr(p_blob,8,1));
    if l_mime in ('image/jpeg','image/jpg') and substr(l_header,1,6)='FFD8FF' then
      p_extension := '.jpg';
    elsif l_mime='image/png' and l_header='89504E470D0A1A0A' then
      p_extension := '.png';
    else
      raise_application_error(-20006, 'الملفات المسموح بها صور JPEG وPNG فقط.');
    end if;
  exception when no_data_found then
    raise_application_error(-20004, 'الصورة غير متاحة في الجلسة الحالية. أعد اختيارها.');
  end;

  procedure upload_card(p_front_name varchar2, p_back_name varchar2) is
    l_emp varchar2(30);
    l_person number;
    l_id number;
    l_existing_id number;
    l_front varchar2(4000);
    l_back varchar2(4000);
    l_front_blob blob;
    l_back_blob blob;
    l_front_ext varchar2(4);
    l_back_ext varchar2(4);
    l_seq varchar2(128);
  begin
    current_employee(l_emp,l_person);
    begin
      select attach_id,attach1,attach2 into l_existing_id,l_front,l_back
        from hrf_person_attachments
       where emp_id=l_emp and person_id=l_person for update;
    exception when no_data_found then null;
    end;
    if l_front is not null and l_back is not null then return; end if;
    -- Validate all missing sides before writing anything to the filesystem.
    if l_front is null then load_image(p_front_name,l_front_blob,l_front_ext); end if;
    if l_back is null then load_image(p_back_name,l_back_blob,l_back_ext); end if;

    -- Reserve the same identity sequence used by page 12; no request is submitted
    -- to its global approval/cleanup procedure. Resolve the local sequence name
    -- from metadata, rather than hard-coding a 42-specific generated name.
    select sequence_name into l_seq from user_tab_identity_cols
     where table_name='HRF_PERSON_ATTACHMENTS_REQUEST' and column_name='REQUEST_ID';
    execute immediate 'select ' || dbms_assert.enquote_name(l_seq,false)
      || '.nextval from dual' into l_id;
    if l_front is null then
      l_front := l_emp || '-' || to_char(l_person,'FM99999999999999999990')
        || '-' || to_char(l_id,'FM99999999999999999990') || '-attach1' || l_front_ext;
      central.blob_to_file(l_front_blob,'ATTACH',l_front);
    end if;
    if l_back is null then
      l_back := l_emp || '-' || to_char(l_person,'FM99999999999999999990')
        || '-' || to_char(l_id,'FM99999999999999999990') || '-attach2' || l_back_ext;
      central.blob_to_file(l_back_blob,'ATTACH',l_back);
    end if;
    if l_existing_id is not null then
      update hrf_person_attachments set attach1=l_front, attach2=l_back,
        date_uploaded=sysdate
       where attach_id=l_existing_id and emp_id=l_emp and person_id=l_person;
    else
      insert into hrf_person_attachments(attach_id,emp_id,person_id,attach1,attach2)
      values(l_id,l_emp,l_person,l_front,l_back);
    end if;
    -- No COMMIT: APEX commits only the successful request. Existing sides and
    -- ATTACH3/ATTACH4 are preserved. No synchronized rows are modified.
  exception when dup_val_on_index then
    raise_application_error(-20007, 'تم تحديث البطاقة من نافذة أخرى. أعد فتح النموذج.');
  end;

  procedure register_games(p_games varchar2) is
    l_emp varchar2(30);
    l_person number;
    l_games varchar2(200);
    l_front varchar2(4000);
    l_back varchar2(4000);
  begin
    current_employee(l_emp,l_person);
    l_games := normalize_games(p_games);
    begin
      select attach1,attach2 into l_front,l_back from hrf_person_attachments
       where emp_id=l_emp and person_id=l_person for update;
    exception when no_data_found then
      raise_application_error(-20008, 'يجب رفع وجه البطاقة وظهرها قبل تقديم الاشتراك.');
    end;
    if l_front is null or l_back is null then
      raise_application_error(-20008, 'يجب رفع وجه البطاقة وظهرها قبل تقديم الاشتراك.');
    end if;
    merge into sports_day_registrations d
    using (select c_event event_code,l_emp emp_id from dual) s
       on (d.event_code=s.event_code and d.emp_id=s.emp_id)
    when matched then update set games=l_games,status='ACTIVE',cancelled_at=null,updated_at=systimestamp
    when not matched then insert(event_code,emp_id,games)
      values(s.event_code,s.emp_id,l_games);
  exception when dup_val_on_index then
    raise_application_error(-20009, 'تم تسجيل الاشتراك من نافذة أخرى. أعد فتح النموذج.');
  end;
end sports_day_pkg;
/
