
  CREATE OR REPLACE EDITIONABLE PACKAGE BODY "EPROMHQ"."MD_PRES_DOCUMENT_PKG" AS
    FUNCTION hash_token(p_token VARCHAR2) RETURN RAW DETERMINISTIC IS
    BEGIN RETURN DBMS_CRYPTO.HASH(UTL_RAW.CAST_TO_RAW(p_token),DBMS_CRYPTO.HASH_SH256); END;

    PROCEDURE free_blob(p_blob IN OUT BLOB) IS BEGIN NULL; END;
    PROCEDURE free_clob(p_clob IN OUT CLOB) IS BEGIN NULL; END;
    PROCEDURE stream_pdf(p_blob IN OUT NOCOPY BLOB,p_name VARCHAR2) IS
    BEGIN
        IF p_blob IS NULL OR DBMS_LOB.GETLENGTH(p_blob)=0 THEN RAISE_APPLICATION_ERROR(-20301,'Prescription PDF is unavailable'); END IF;
        OWA_UTIL.MIME_HEADER('application/pdf',FALSE);
        HTP.P('Content-Length: '||DBMS_LOB.GETLENGTH(p_blob));
        HTP.P('Content-Disposition: inline; filename="'||REPLACE(NVL(p_name,'prescription.pdf'),'"','')||'"');
        OWA_UTIL.HTTP_HEADER_CLOSE;
        WPG_DOCLOAD.DOWNLOAD_FILE(p_blob);
    END;

    FUNCTION can_manage_document(p_request_id NUMBER,p_actor VARCHAR2) RETURN BOOLEAN IS
        l_owner VARCHAR2(30); l_user VARCHAR2(128);
    BEGIN
        SELECT employee_number INTO l_owner FROM md_pres_request WHERE request_id=p_request_id;
        IF UPPER(TRIM(p_actor))=UPPER(TRIM(l_owner)) THEN RETURN TRUE; END IF;
        BEGIN
            SELECT username INTO l_user FROM users WHERE emp_id=l_owner FETCH FIRST 1 ROW ONLY;
            IF UPPER(TRIM(p_actor))=UPPER(TRIM(l_user)) THEN RETURN TRUE; END IF;
        EXCEPTION WHEN NO_DATA_FOUND THEN NULL; END;
        RETURN md_pres_request_pkg.doctor_can_view(p_request_id,p_actor)='Y';
    EXCEPTION WHEN NO_DATA_FOUND THEN RETURN FALSE;
    END;

    PROCEDURE generate_document(p_request_id NUMBER,p_actor VARCHAR2) IS
        l_status VARCHAR2(30); l_request_no VARCHAR2(40); l_ben VARCHAR2(720); l_emp VARCHAR2(30); l_doc_ver NUMBER; l_file VARCHAR2(500); l_base VARCHAR2(4000); l_aop VARCHAR2(4000); l_html CLOB; l_template BLOB; l_template64 CLOB; l_sql CLOB; l_pdf BLOB; l_hash RAW(32); l_token_raw RAW(32); l_token_b64 RAW(32767); l_token VARCHAR2(100); l_token_hash RAW(32); l_qr VARCHAR2(4000); l_doc_id NUMBER; l_err VARCHAR2(4000); l_binds wwv_flow_plugin_util.t_bind_list; l_dst INTEGER:=1; l_src INTEGER:=1; l_ctx INTEGER:=DBMS_LOB.DEFAULT_LANG_CTX; l_warn INTEGER:=0;
    BEGIN
        SELECT status,request_no,beneficiary_name_snapshot,employee_number INTO l_status,l_request_no,l_ben,l_emp FROM md_pres_request WHERE request_id=p_request_id FOR UPDATE;
        IF l_status NOT IN ('APPROVED','PARTIALLY_APPROVED') THEN RAISE_APPLICATION_ERROR(-20302,'Only approved prescription requests can generate a PDF'); END IF;
        SELECT NVL(MAX(document_version),0)+1 INTO l_doc_ver FROM md_pres_document WHERE request_id=p_request_id;
        SELECT config_value INTO l_base FROM md_pres_config WHERE config_key='PRESCRIPTION_PUBLIC_BASE_URL';
        BEGIN SELECT config_value INTO l_aop FROM md_referal_config WHERE config_key='AOP_URL'; EXCEPTION WHEN NO_DATA_FOUND THEN l_aop:=NULL; END;
        IF l_aop IS NULL THEN RAISE_APPLICATION_ERROR(-20303,'AOP URL is not configured'); END IF;
        l_file:='prescription-'||l_request_no||'-v'||l_doc_ver||'.pdf';
        l_token_raw:=DBMS_CRYPTO.RANDOMBYTES(32);
        l_token_b64:=UTL_ENCODE.BASE64_ENCODE(l_token_raw);
        l_token:=RTRIM(REPLACE(REPLACE(REPLACE(REPLACE(UTL_RAW.CAST_TO_VARCHAR2(l_token_b64),CHR(13),''),CHR(10),''),'+','-'),'/','_'),'=');
        l_token_hash:=hash_token(l_token);
        l_qr:=RTRIM(l_base,'/')||'/f?p=104:113:0::::P113_TOKEN:'||l_token;
        l_html:='<!doctype html><html><head><meta charset="utf-8"><style>body{font-family:Arial;direction:rtl}table{width:100%;border-collapse:collapse}td,th{border:1px solid #777;padding:6px}</style></head><body><h2>روشتة طبية</h2><p>رقم الطلب: {request_no}</p><p>الموظف: {employee_name} ({employee_number})</p><p>المستفيد: {beneficiary_name} - Person ID: {beneficiary_person_id}</p><p>الطبيب: {doctor}</p><table><tr><th>الدواء</th><th>الوحدة</th><th>الكمية</th><th>طريقة الصرف</th><th>الصيدلية</th></tr>{#items}<tr><td>{medicine_name}</td><td>{unit_name}</td><td>{quantity}</td><td>{dispense_mode}</td><td>{pharmacy_name}</td></tr>{/items}</table><p>التحقق الإلكتروني:</p><img src="data:image/png;base64,{qr_image_base64}" width="140"></body></html>';
        DBMS_LOB.CREATETEMPORARY(l_template,TRUE);
        DBMS_LOB.CONVERTTOBLOB(l_template,l_html,DBMS_LOB.LOBMAXSIZE,l_dst,l_src,NLS_CHARSET_ID('AL32UTF8'),l_ctx,l_warn);
        l_template64:=APEX_WEB_SERVICE.BLOB2CLOBBASE64(l_template);
        l_sql:=q'~SELECT :B_FILENAME AS "filename", CURSOR(SELECT r.request_no AS "request_no", r.employee_name_snapshot AS "employee_name", r.employee_number AS "employee_number", r.beneficiary_name_snapshot AS "beneficiary_name", r.beneficiary_person_id AS "beneficiary_person_id", NVL((SELECT MAX(i.reviewed_by) FROM md_pres_request_item i WHERE i.request_id=r.request_id),'') AS "doctor", APEX_WEB_SERVICE.BLOB2CLOBBASE64(APEX_BARCODE.GET_QRCODE_PNG(:B_QR_URL,1,4,'H','#000000','#FFFFFF')) AS "qr_image_base64", CURSOR(SELECT i.medicine_name_snapshot AS "medicine_name", i.unit_name_snapshot AS "unit_name", i.quantity AS "quantity", i.dispense_mode AS "dispense_mode", NVL(i.pharmacy_name_snapshot,'صرف يومي') AS "pharmacy_name" FROM md_pres_request_item i WHERE i.request_id=r.request_id AND i.doctor_decision='APPROVED' AND i.dispense_mode IN ('DAILY','PHARMACY') ORDER BY i.line_no) AS "items" FROM md_pres_request r WHERE r.request_id=TO_NUMBER(:B_REQUEST_ID) GROUP BY r.request_no,r.employee_name_snapshot,r.employee_number,r.beneficiary_name_snapshot,r.beneficiary_person_id,r.request_id) AS "data" FROM dual~';
        l_binds(1).name:='B_FILENAME'; l_binds(1).value:=l_file;
        l_binds(2).name:='B_QR_URL'; l_binds(2).value:=l_qr;
        l_binds(3).name:='B_REQUEST_ID'; l_binds(3).value:=TO_CHAR(p_request_id);
        l_pdf:=AOP_API_PKG.PLSQL_CALL_TO_AOP(P_DATA_TYPE=>'SQL',P_DATA_SOURCE=>l_sql,P_TEMPLATE_TYPE=>'CLOB_BASE64',P_TEMPLATE_SOURCE=>l_template64,P_OUTPUT_TYPE=>'pdf',P_OUTPUT_FILENAME=>l_file,P_OUTPUT_TO=>'BLOB',P_BINDS=>l_binds,P_APP_ID=>200,P_PAGE_ID=>169,P_USER_NAME=>NVL(V('APP_USER'),'MIS_PRESCRIPTION_JOB'),P_AOP_URL=>l_aop,P_INIT_CODE=>q'[aop_api_pkg.g_template_type := 'html';]');
        IF l_pdf IS NULL OR DBMS_LOB.GETLENGTH(l_pdf)=0 THEN RAISE_APPLICATION_ERROR(-20304,'AOP returned an empty prescription PDF'); END IF;
        l_hash:=DBMS_CRYPTO.HASH(l_pdf,DBMS_CRYPTO.HASH_SH256);
        UPDATE md_pres_document SET token_status='REVOKED',token_revoked_at=SYSTIMESTAMP WHERE request_id=p_request_id AND token_status='ACTIVE';
        INSERT INTO md_pres_document(request_id,prescription_id,document_version,prescription_no,pdf_blob,mime_type,file_name,file_size,file_sha256,public_token_hash,token_status,token_created_at,created_by)
        SELECT p_request_id,prescription_id,l_doc_ver,l_request_no,l_pdf,'application/pdf',l_file,DBMS_LOB.GETLENGTH(l_pdf),l_hash,l_token_hash,'ACTIVE',SYSTIMESTAMP,SUBSTR(p_actor,1,128) FROM md_pres_request WHERE request_id=p_request_id;
        SELECT document_id INTO l_doc_id FROM md_pres_document WHERE request_id=p_request_id AND document_version=l_doc_ver;
        INSERT INTO md_pres_document_item(document_id,source_item_id,line_no,medicine_name_snapshot,unit_name_snapshot,quantity,dispense_mode,pharmacy_name_snapshot)
        SELECT l_doc_id,item_id,line_no,medicine_name_snapshot,unit_name_snapshot,quantity,dispense_mode,pharmacy_name_snapshot
          FROM md_pres_request_item
         WHERE request_id=p_request_id
           AND doctor_decision='APPROVED'
           AND dispense_mode IN ('DAILY','PHARMACY')
         ORDER BY line_no;
        UPDATE md_pres_request SET document_status='READY',document_error=NULL,updated_at=SYSTIMESTAMP,updated_by=p_actor WHERE request_id=p_request_id;
        free_blob(l_template); free_blob(l_pdf); free_clob(l_template64); free_clob(l_sql);
    EXCEPTION WHEN OTHERS THEN
        l_err:=SUBSTR(DBMS_UTILITY.FORMAT_ERROR_STACK,1,4000);
        UPDATE md_pres_request SET document_status='ERROR',document_error=l_err,updated_at=SYSTIMESTAMP,updated_by=p_actor WHERE request_id=p_request_id;
        free_blob(l_template); free_blob(l_pdf); free_clob(l_template64); free_clob(l_sql); RAISE;
    END;

    PROCEDURE download_employee_document(p_request_id NUMBER,p_app_user VARCHAR2) IS l_blob BLOB; l_name VARCHAR2(500); BEGIN
        IF NOT can_manage_document(p_request_id,p_app_user) THEN RAISE_APPLICATION_ERROR(-20305,'You are not authorized to download this prescription'); END IF;
        SELECT pdf_blob,file_name INTO l_blob,l_name FROM md_pres_document WHERE request_id=p_request_id AND token_status='ACTIVE' AND pdf_blob IS NOT NULL ORDER BY document_version DESC FETCH FIRST 1 ROW ONLY;
        stream_pdf(l_blob,l_name);
    EXCEPTION WHEN NO_DATA_FOUND THEN RAISE_APPLICATION_ERROR(-20306,'Active prescription PDF was not found'); END;

    PROCEDURE create_share_url(p_request_id NUMBER,p_app_user VARCHAR2,p_public_url OUT VARCHAR2) IS l_hash RAW(32); l_token VARCHAR2(100); l_doc NUMBER; l_base VARCHAR2(4000); BEGIN
        IF NOT can_manage_document(p_request_id,p_app_user) THEN RAISE_APPLICATION_ERROR(-20307,'You are not authorized to share this prescription'); END IF;
        SELECT document_id INTO l_doc FROM md_pres_document WHERE request_id=p_request_id AND token_status='ACTIVE' ORDER BY document_version DESC FETCH FIRST 1 ROW ONLY; SELECT config_value INTO l_base FROM md_pres_config WHERE config_key='PRESCRIPTION_PUBLIC_BASE_URL';
        l_token:=LOWER(RAWTOHEX(DBMS_CRYPTO.RANDOMBYTES(32))); l_hash:=hash_token(l_token); UPDATE md_pres_document SET share_token_hash=l_hash,token_created_at=SYSTIMESTAMP WHERE document_id=l_doc; p_public_url:=RTRIM(l_base,'/')||'/f?p=104:113:0::::P113_TOKEN:'||l_token;
    EXCEPTION WHEN NO_DATA_FOUND THEN RAISE_APPLICATION_ERROR(-20308,'Active prescription document was not found'); END;

    PROCEDURE send_document_email(p_request_id NUMBER,p_app_user VARCHAR2,p_recipient VARCHAR2) IS l_blob BLOB; l_name VARCHAR2(500); l_mail_id NUMBER; BEGIN
        IF NOT can_manage_document(p_request_id,p_app_user) THEN RAISE_APPLICATION_ERROR(-20309,'You are not authorized to email this prescription'); END IF;
        IF NOT REGEXP_LIKE(TRIM(p_recipient),'^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,63}$') THEN RAISE_APPLICATION_ERROR(-20311,'A valid recipient email is required'); END IF;
        SELECT pdf_blob,file_name INTO l_blob,l_name FROM md_pres_document WHERE request_id=p_request_id AND token_status='ACTIVE' ORDER BY document_version DESC FETCH FIRST 1 ROW ONLY;
        l_mail_id:=APEX_MAIL.SEND(p_to=>p_recipient,p_from=>'no-reply@eprom.com.eg',p_subj=>'Prescription '||p_request_id,p_body=>'Attached is the approved prescription.'); APEX_MAIL.ADD_ATTACHMENT(l_mail_id,l_blob,'application/pdf',l_name); APEX_MAIL.PUSH_QUEUE;
    EXCEPTION WHEN NO_DATA_FOUND THEN RAISE_APPLICATION_ERROR(-20309,'Active prescription document was not found'); END;

    PROCEDURE resolve_public_token(p_token VARCHAR2,p_request_id OUT NUMBER,p_request_no OUT VARCHAR2,p_beneficiary_name OUT VARCHAR2,p_doctor OUT VARCHAR2,p_status OUT VARCHAR2) IS
        l_hash RAW(32); l_old_doctor VARCHAR2(128);
    BEGIN
        l_hash:=hash_token(TRIM(p_token));
        SELECT d.request_id,r.request_no,r.beneficiary_name_snapshot,NVL((SELECT MAX(reviewed_by) FROM md_pres_request_item i WHERE i.request_id=r.request_id),'') ,r.status
          INTO p_request_id,p_request_no,p_beneficiary_name,p_doctor,p_status
          FROM md_pres_document d JOIN md_pres_request r ON r.request_id=d.request_id
         WHERE (d.public_token_hash=l_hash OR d.share_token_hash=l_hash) AND d.token_status='ACTIVE' AND d.pdf_blob IS NOT NULL;
    EXCEPTION WHEN NO_DATA_FOUND THEN
        BEGIN
            SELECT NVL(MAX(i.reviewed_by),'الطبيب المعتمد') INTO l_old_doctor
              FROM md_pres_document d JOIN md_pres_request_item i ON i.request_id=d.request_id
             WHERE (d.public_token_hash=l_hash OR d.share_token_hash=l_hash) AND d.token_status='REVOKED';
            IF l_old_doctor IS NOT NULL THEN
                RAISE_APPLICATION_ERROR(-20310,'قام الدكتور '||l_old_doctor||' بتعديل الروشتة وإصدار نسخة أحدث؛ برجاء تجاهل هذه النسخة وفتح أحدث نسخة صادرة من الدكتور.');
            END IF;
        EXCEPTION WHEN NO_DATA_FOUND THEN NULL; END;
        RAISE_APPLICATION_ERROR(-20310,'هذه النسخة من الروشتة غير صالحة أو تم تعديلها. برجاء تجاهلها وفتح أحدث نسخة صادرة من الدكتور.');
    END;

    PROCEDURE download_public_document(p_token VARCHAR2) IS l_request NUMBER; l_no VARCHAR2(40); l_ben VARCHAR2(720); l_doc VARCHAR2(128); l_status VARCHAR2(30); l_blob BLOB; l_name VARCHAR2(500); BEGIN resolve_public_token(p_token,l_request,l_no,l_ben,l_doc,l_status); SELECT pdf_blob,file_name INTO l_blob,l_name FROM md_pres_document WHERE request_id=l_request AND token_status='ACTIVE' ORDER BY document_version DESC FETCH FIRST 1 ROW ONLY; stream_pdf(l_blob,l_name); END;
END md_pres_document_pkg;
/
