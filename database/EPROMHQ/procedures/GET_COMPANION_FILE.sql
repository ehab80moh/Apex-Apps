
  CREATE OR REPLACE EDITIONABLE PROCEDURE "EPROMHQ"."GET_COMPANION_FILE" (
    p_companion_id IN NUMBER,          -- رقم الـ COMPANION_ID
    p_attach_no    IN PLS_INTEGER DEFAULT 1  -- 1 = EXTRA_ATTACH1, 2 = EXTRA_ATTACH2
) IS
  l_blob_content   BLOB;                  -- الملف نفسه
  l_mime_type      VARCHAR2(100) := 'image/jpeg';  -- نوع عام
  l_file_name      VARCHAR2(200);         -- اسم الملف الظاهر في الـ Download
BEGIN
  IF p_attach_no = 2 THEN
     -- المرفق الثاني
     SELECT extra_attach2
       INTO l_blob_content
       FROM vac_winter_companions
      WHERE companion_id = p_companion_id;

     l_file_name := 'ATTACH2_' || p_companion_id || '.jpeg';
  ELSE
     -- المرفق الأول (الافتراضي)
     SELECT extra_attach1
       INTO l_blob_content
       FROM vac_winter_companions
      WHERE companion_id = p_companion_id;

     l_file_name := 'ATTACH1_' || p_companion_id || '.jpeg';
  END IF;

  -- لو طلع الـ BLOB فاضي
  IF l_blob_content IS NULL THEN
     htp.p('File not found.');
     RETURN;
  END IF;

  -- تجهيز الهيدر للتحميل
  sys.htp.init;
  sys.owa_util.mime_header(l_mime_type, FALSE);
  sys.htp.p('Content-Length: ' || dbms_lob.getlength(l_blob_content));
  sys.htp.p('Content-Disposition: attachment; filename="' || l_file_name || '"');
  sys.owa_util.http_header_close;

  -- تنزيل الملف
  sys.WPG_DOCLOAD.download_file(l_blob_content);
      APEX_UTIL.SET_SESSION_STATE('P45_COMPANION_ID_1','');
            APEX_UTIL.SET_SESSION_STATE('P45_COMPANION_ID_2','');

  --File is downloaded
  apex_application.stop_apex_engine;

EXCEPTION
  WHEN apex_application.e_stop_apex_engine THEN
    NULL;
  WHEN NO_DATA_FOUND THEN
    htp.p('File not found.');
  WHEN OTHERS THEN
    htp.p('Error downloading file.');
END get_companion_file;
/
