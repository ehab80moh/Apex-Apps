
  CREATE OR REPLACE EDITIONABLE TRIGGER "EPROMHQ"."SUP_SUPPLIERS_MIN_ATTACHMENTS"
before update of status on sup_suppliers
for each row
 WHEN (new.status = 'COMPLETE') declare
    l_cnt number;
begin
    select count(*)
    into l_cnt
    from sup_suppliers_attaches
    where supplier_id = :new.supplier_id;

    if l_cnt < 8 then
        raise_application_error(-20001,
            'Supplier must have at least 8 attachments');
    end if;
end;

/
ALTER TRIGGER "EPROMHQ"."SUP_SUPPLIERS_MIN_ATTACHMENTS" DISABLE;
