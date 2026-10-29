
  CREATE OR REPLACE EDITIONABLE TRIGGER "EPROMHQ"."SUP_ATTACH_COMPLETE_IF_ACTIVE"
AFTER INSERT OR DELETE
ON sup_suppliers_attaches
FOR EACH ROW
DECLARE
    l_supplier_id   sup_suppliers.supplier_id%TYPE;
    l_attach_cnt    NUMBER;
BEGIN
    /* Determine supplier_id safely */
    l_supplier_id :=
        CASE
            WHEN INSERTING THEN :NEW.supplier_id
            ELSE :OLD.supplier_id
        END;

    /* Count DISTINCT required attachments (exclude certificate) */
    SELECT COUNT(DISTINCT a.static_name)
    INTO   l_attach_cnt
    FROM   sup_suppliers_attaches a
    WHERE  a.supplier_id = l_supplier_id
    AND    a.static_name IN (
           SELECT t.static_name
           FROM   sup_attachment_types t
           WHERE  t.display_name <> 'Construction & Building Contractors Certificate'
    );

    /* First-time completion only */
    UPDATE sup_suppliers
       SET status      = 'COMPLETE',
           is_modified = 'N'
     WHERE supplier_id = l_supplier_id
       AND status      = 'ACTIVE'
       AND l_attach_cnt >= 8;

EXCEPTION
    WHEN OTHERS THEN
        /* NEVER block attachment transaction */
        NULL;
END trg_sup_attach_complete;

/
ALTER TRIGGER "EPROMHQ"."SUP_ATTACH_COMPLETE_IF_ACTIVE" ENABLE;
