
  CREATE OR REPLACE EDITIONABLE PACKAGE "EPROMHQ"."PRF_EMP_CARDS_PKG" authid definer as
  function file_name(p_emp_id varchar2,p_slot number) return varchar2;
  function attachments_link(p_emp_id varchar2,p_count number) return varchar2;
  function gallery_html(p_emp_id varchar2) return clob;
  function summary_html return clob;
  procedure download_file(p_emp_id varchar2,p_slot number);
end prf_emp_cards_pkg;
/
