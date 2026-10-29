
  CREATE OR REPLACE EDITIONABLE PROCEDURE "EPROMHQ"."SUP_DELETE_PENDING_SUPPLIERS" as
  l_deleted number := 0;
begin
  -- Archive first
  insert into sup_deleted_pending_suppliers (company_name, contact_name, mobile, email)
  select company_name,
         contact_person,      -- change this if your column name differs
         headoff_mobile,
         headoff_email
    from sup_suppliers s
   where status = 'PENDING'
	 and   s.supplier_id not in (select ser.supplier_id from sup_services ser)
     and created_on >= trunc(sysdate) - 1;

  -- Then delete from main table
  delete from sup_suppliers
   where status = 'PENDING'
     and created_on >= trunc(sysdate) -1;

  l_deleted := sql%rowcount;

  dbms_output.put_line(l_deleted || ' pending suppliers archived and deleted.');

  commit;
end sup_delete_pending_suppliers;
/
