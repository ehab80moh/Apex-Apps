
  CREATE OR REPLACE EDITIONABLE PROCEDURE "EPROMHQ"."SUP_SEND_MISSING_DOCS_SMS_ALL"
IS
    CURSOR c_suppliers IS
        SELECT s.supplier_id,
               s.headoff_mobile
        FROM   sup_suppliers s
        WHERE  s.headoff_mobile IS NOT NULL;

    l_missing_list   VARCHAR2(4000);
    l_missing_count  NUMBER;
    l_message        VARCHAR2(4000);
    l_sms_result     VARCHAR2(200);
BEGIN
    FOR r IN c_suppliers LOOP
        BEGIN
            /* --------------------------------------------
               Count missing attachments (EXCLUDING certificate)
            ---------------------------------------------*/
            SELECT COUNT(*)
            INTO   l_missing_count
            FROM   sup_attachment_types t
            WHERE  t.display_name <> 'Construction & Building Contractors Certificate'
            AND    t.static_name NOT IN (
                   SELECT a.static_name
                   FROM   sup_suppliers_attaches a
                   WHERE  a.supplier_id = r.supplier_id
            );

            /* --------------------------------------------
               Apply COUNT rule: only 1..7
            ---------------------------------------------*/
            IF l_missing_count BETWEEN 1 AND 7 THEN

                /* Get missing list for SMS */
                SELECT LISTAGG(t.display_name, ', ')
                       WITHIN GROUP (ORDER BY t.display_name)
                INTO   l_missing_list
                FROM   sup_attachment_types t
                WHERE  t.display_name <> 'Construction & Building Contractors Certificate'
                AND    t.static_name NOT IN (
                       SELECT a.static_name
                       FROM   sup_suppliers_attaches a
                       WHERE  a.supplier_id = r.supplier_id
                );

                /* Build message */
                l_message :=
                    'Dear Supplier, the following documents are missing ('
                    || l_missing_count || '): '
                    || l_missing_list
                    || '. Please upload them to complete your profile.';

                /* Send SMS */
                l_sms_result :=
                    central.sms_pkg.send_single(
                      l_message,
                        r.headoff_mobile
                    );
            END IF;

        EXCEPTION
            WHEN OTHERS THEN
                -- Optional: log and continue
                NULL;
        END;
    END LOOP;
END sup_send_missing_docs_sms_all;
/
