
  CREATE OR REPLACE EDITIONABLE FUNCTION "EPROMHQ"."GET_FILE_EXTENSION" (p_mime_type IN VARCHAR2)
RETURN VARCHAR2
IS
    v_ext VARCHAR2(10);
BEGIN
    CASE LOWER(p_mime_type)
        WHEN 'image/jpeg' THEN v_ext := '.jpg';
        WHEN 'image/jpg'  THEN v_ext := '.jpg';
        WHEN 'image/png'  THEN v_ext := '.png';
        WHEN 'image/gif'  THEN v_ext := '.gif';
        WHEN 'image/bmp'  THEN v_ext := '.bmp';
        WHEN 'image/webp' THEN v_ext := '.webp';
        WHEN 'application/pdf' THEN v_ext := '.pdf';
        WHEN 'application/msword' THEN v_ext := '.doc';
        WHEN 'application/vnd.openxmlformats-officedocument.wordprocessingml.document' THEN v_ext := '.docx';
        WHEN 'application/vnd.ms-excel' THEN v_ext := '.xls';
        WHEN 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet' THEN v_ext := '.xlsx';
        WHEN 'text/plain' THEN v_ext := '.txt';
        WHEN 'text/csv' THEN v_ext := '.csv';
        WHEN 'application/zip' THEN v_ext := '.zip';
        ELSE
            -- Default fallback if unknown MIME type
            v_ext := '';
    END CASE;
    RETURN v_ext;
END;
/
