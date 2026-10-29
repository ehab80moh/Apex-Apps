
  CREATE OR REPLACE EDITIONABLE TRIGGER "EPROMHQ"."SUP_SUP_ATTACH_BIU"
before insert or update on sup_suppliers_attaches
for each row
declare
    l_ext varchar2(10);
begin
    if :new.original_name is not null then
        l_ext := lower(substr(:new.original_name,
                     instr(:new.original_name, '.', -1)));
    else
        l_ext := '.dat';
    end if;

    :new.file_name := :new.supplier_id || '-' || :new.static_name || l_ext;
end;

/
ALTER TRIGGER "EPROMHQ"."SUP_SUP_ATTACH_BIU" ENABLE;
