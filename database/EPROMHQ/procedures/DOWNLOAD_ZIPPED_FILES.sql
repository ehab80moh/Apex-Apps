
  CREATE OR REPLACE EDITIONABLE PROCEDURE "EPROMHQ"."DOWNLOAD_ZIPPED_FILES" (p_source_id IN NUMBER) IS
    l_temp_blob     BLOB;             -- Temporary blob for file content
    l_file_name     VARCHAR2(255);    -- File name
    l_mime_type     VARCHAR2(255);    -- MIME type
    l_zip_file_name VARCHAR2(255) := 'files.zip'; -- Name of the zip file to download
  l_zip  blob;
    -- Cursor to fetch all files for the given SOURCE_ID
    CURSOR c_files IS
        SELECT FILE_BLOB, FILE_NAME, MIME_TYPE
        FROM EPROMHQ.LAGD_ATTACHMENT
        WHERE SOURCE_ID = p_source_id;

BEGIN
   for cur_rec in c_files loop
    if cur_rec.FILE_BLOB is not null then
    apex_zip.add_file(p_zipped_blob => l_zip,
                      p_file_name   => cur_rec.FILE_NAME,
                      p_content     => cur_rec.FILE_BLOB);
     end if;
  end loop;
   -- Close the zip file.
    apex_zip.finish(p_zipped_blob => l_zip);

    -- Respond to the client with the zipped file
    sys.HTP.init;
    sys.OWA_UTIL.mime_header('application/zip', FALSE);
    sys.HTP.p('Content-Disposition: attachment; filename="' || l_zip_file_name || '"');
    sys.HTP.p('Content-Length: ' || DBMS_LOB.getlength(l_zip));
    sys.OWA_UTIL.http_header_close;

    -- Send the zip BLOB for download
    sys.WPG_DOCLOAD.download_file(l_zip);

    -- Free the temporary BLOB
    DBMS_LOB.FREETEMPORARY(l_zip);

    -- Stop the APEX engine
    apex_application.stop_apex_engine;


END;
/
