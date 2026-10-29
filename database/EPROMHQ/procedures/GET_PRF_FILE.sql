
  CREATE OR REPLACE EDITIONABLE PROCEDURE "EPROMHQ"."GET_PRF_FILE" (p_file_id  IN VARCHAR2) IS --The parameter will be the ID of the file in my document table
  l_blob_content  prf_attachment.FILE_BLOB%TYPE;       --The BLOB FILE
  l_mime_type     prf_attachment.MIME_TYPE%TYPE;   --The MIMETYPE of the File
  l_name_document  prf_attachment.FILE_NAME%TYPE;        --The name of the file
BEGIN
  SELECT FILE_BLOB,
         MIME_TYPE,
         FILE_NAME
  INTO   l_blob_content,
         l_mime_type,
         l_name_document
  FROM   prf_attachment
  WHERE  ATTACH_ID = p_file_id; --SELECT the BLOB file and its information based on the ID from the document table

  -- This below creates the download
  sys.HTP.init;
  sys.OWA_UTIL.mime_header(l_mime_type, FALSE);
  sys.HTP.p('Content-Length: ' || DBMS_LOB.getlength(l_blob_content));
  sys.HTP.p('Content-Disposition: attachment; filename="' || l_name_document || '"'); --Create a download with the name of the original file
  sys.OWA_UTIL.http_header_close;                                                    --If you remove "attachment;", the file will not be downloaded automatically, but opened in a new Tab

  sys.WPG_DOCLOAD.download_file(l_blob_content);                                     --File is downloaded
  apex_application.stop_apex_engine;
EXCEPTION
  WHEN apex_application.e_stop_apex_engine THEN
    NULL;
  WHEN OTHERS THEN
    HTP.p('Whoops');
END;
/
