
  CREATE OR REPLACE EDITIONABLE PACKAGE BODY "EPROMHQ"."INV_WH_PKG" AS

    PROCEDURE RECEIVE_STOCK (
        p_wh_id        IN NUMBER,
        p_client_id    IN NUMBER,
        p_project_id   IN NUMBER,
        p_location_id  IN NUMBER,
        p_warehouse_id IN NUMBER DEFAULT NULL,
        p_quantity     IN NUMBER,
        p_remarks      IN VARCHAR2 DEFAULT NULL
    ) IS
    BEGIN
        IF p_quantity IS NULL OR p_quantity <= 0 THEN
            RAISE_APPLICATION_ERROR(-20001, 'Quantity to receive must be greater than zero.');
        END IF;

        IF p_wh_id IS NULL THEN
            RAISE_APPLICATION_ERROR(-20002, 'WH_ID (Material) is required.');
        END IF;

        MERGE INTO INV_WH_STOCK_BALANCES b
        USING (
            SELECT p_wh_id        AS wh_id,
                   p_client_id    AS client_id,
                   p_project_id   AS project_id,
                   p_location_id  AS location_id,
                   p_warehouse_id AS warehouse_id
              FROM dual
        ) src
        ON (
            b.wh_id = src.wh_id
            AND b.client_id = src.client_id
            AND b.project_id = src.project_id
            AND b.location_id = src.location_id
            AND NVL(b.warehouse_id, -1) = NVL(src.warehouse_id, -1)
        )
        WHEN MATCHED THEN
            UPDATE SET
                b.quantity           = b.quantity + p_quantity,
                b.last_verified_date = SYSDATE,
                b.remarks            = NVL(p_remarks, b.remarks),
                b.updated_at         = SYSDATE
        WHEN NOT MATCHED THEN
            INSERT (
                wh_id,
                client_id,
                project_id,
                location_id,
                warehouse_id,
                quantity,
                counted_quantity,
                last_verified_date,
                remarks,
                created_at,
                updated_at
            ) VALUES (
                src.wh_id,
                src.client_id,
                src.project_id,
                src.location_id,
                src.warehouse_id,
                p_quantity,
                0,
                SYSDATE,
                p_remarks,
                SYSDATE,
                SYSDATE
            );
    END RECEIVE_STOCK;

    PROCEDURE ADJUST_STOCK (
        p_balance_id   IN NUMBER,
        p_new_quantity IN NUMBER,
        p_remarks      IN VARCHAR2 DEFAULT NULL
    ) IS
    BEGIN
        IF p_new_quantity IS NULL OR p_new_quantity < 0 THEN
            RAISE_APPLICATION_ERROR(-20003, 'New quantity cannot be negative or null.');
        END IF;

        UPDATE INV_WH_STOCK_BALANCES
           SET quantity           = p_new_quantity,
               last_verified_date = SYSDATE,
               remarks            = NVL(p_remarks, remarks),
               updated_at         = SYSDATE
         WHERE balance_id = p_balance_id;

        IF SQL%ROWCOUNT = 0 THEN
            RAISE_APPLICATION_ERROR(-20004, 'Stock balance line not found for ID: ' || p_balance_id);
        END IF;
    END ADJUST_STOCK;

    PROCEDURE TRANSFER_STOCK (
        p_from_balance_id IN NUMBER,
        p_to_client_id    IN NUMBER,
        p_to_project_id   IN NUMBER,
        p_to_location_id  IN NUMBER,
        p_to_warehouse_id IN NUMBER DEFAULT NULL,
        p_quantity        IN NUMBER,
        p_remarks         IN VARCHAR2 DEFAULT NULL
    ) IS
        v_from_wh_id NUMBER;
        v_from_qty   NUMBER;
    BEGIN
        IF p_quantity IS NULL OR p_quantity <= 0 THEN
            RAISE_APPLICATION_ERROR(-20005, 'Transfer quantity must be greater than zero.');
        END IF;

        SELECT wh_id, quantity
          INTO v_from_wh_id, v_from_qty
          FROM INV_WH_STOCK_BALANCES
         WHERE balance_id = p_from_balance_id
           FOR UPDATE;

        IF v_from_qty < p_quantity THEN
            RAISE_APPLICATION_ERROR(-20006, 'Insufficient stock. Available: ' || v_from_qty || ', Requested: ' || p_quantity);
        END IF;

        UPDATE INV_WH_STOCK_BALANCES
           SET quantity   = quantity - p_quantity,
               updated_at = SYSDATE
         WHERE balance_id = p_from_balance_id;

        RECEIVE_STOCK(
            p_wh_id        => v_from_wh_id,
            p_client_id    => p_to_client_id,
            p_project_id   => p_to_project_id,
            p_location_id  => p_to_location_id,
            p_warehouse_id => p_to_warehouse_id,
            p_quantity     => p_quantity,
            p_remarks      => NVL(p_remarks, 'Transfer from balance #' || p_from_balance_id)
        );
    END TRANSFER_STOCK;

    PROCEDURE INCREMENT_COUNT (
        p_balance_id IN NUMBER,
        p_qty        IN NUMBER DEFAULT 1,
        o_new_count  OUT NUMBER
    ) IS
        v_add_qty NUMBER := NVL(p_qty, 1);
    BEGIN
        IF v_add_qty <= 0 THEN
            RAISE_APPLICATION_ERROR(-20010, 'Count increment must be greater than zero.');
        END IF;

        UPDATE INV_WH_STOCK_BALANCES
           SET counted_quantity   = counted_quantity + v_add_qty,
               last_verified_date = SYSDATE,
               updated_at         = SYSDATE
         WHERE balance_id = p_balance_id
        RETURNING counted_quantity INTO o_new_count;

        IF SQL%ROWCOUNT = 0 THEN
            RAISE_APPLICATION_ERROR(-20011, 'Stock balance line not found for ID: ' || p_balance_id);
        END IF;
    END INCREMENT_COUNT;

    -- Multi-criteria reset procedure
    PROCEDURE RESET_COUNTS (
        p_warehouse_id IN NUMBER DEFAULT NULL,
        p_location_id  IN NUMBER DEFAULT NULL,
        p_client_id    IN NUMBER DEFAULT NULL,
        p_project_id   IN NUMBER DEFAULT NULL,
        p_wh_id        IN NUMBER DEFAULT NULL,
        o_reset_count  OUT NUMBER
    ) IS
        v_resolved_wh_id NUMBER := p_wh_id;
    BEGIN
        IF p_wh_id IS NOT NULL THEN
            BEGIN
                SELECT wh_id INTO v_resolved_wh_id
                  FROM INV_WH_MASTER_DATA
                 WHERE wh_id = p_wh_id;
            EXCEPTION
                WHEN NO_DATA_FOUND THEN
                    BEGIN
                        SELECT wh_id INTO v_resolved_wh_id
                          FROM INV_WH_MASTER_DATA
                         WHERE material_code = TO_CHAR(p_wh_id);
                    EXCEPTION
                        WHEN NO_DATA_FOUND THEN
                            v_resolved_wh_id := p_wh_id;
                    END;
            END;
        END IF;

        UPDATE INV_WH_STOCK_BALANCES
           SET counted_quantity = 0,
               updated_at       = SYSDATE
         WHERE (p_warehouse_id IS NULL OR warehouse_id = p_warehouse_id)
           AND (p_location_id  IS NULL OR location_id  = p_location_id)
           AND (p_client_id    IS NULL OR client_id    = p_client_id)
           AND (p_project_id   IS NULL OR project_id   = p_project_id)
           AND (v_resolved_wh_id IS NULL OR wh_id = v_resolved_wh_id);

        o_reset_count := SQL%ROWCOUNT;
    END RESET_COUNTS;

    -- Backward compatibility wrapper for existing Page 300 call
    PROCEDURE RESET_COUNTS (
        p_warehouse_id IN NUMBER DEFAULT NULL,
        p_wh_id        IN NUMBER DEFAULT NULL
    ) IS
        v_dummy NUMBER;
    BEGIN
        RESET_COUNTS(
            p_warehouse_id => p_warehouse_id,
            p_location_id  => NULL,
            p_client_id    => NULL,
            p_project_id   => NULL,
            p_wh_id        => p_wh_id,
            o_reset_count  => v_dummy
        );
    END RESET_COUNTS;

    PROCEDURE RECONCILE_STOCK (
        p_balance_id IN NUMBER,
        p_remarks    IN VARCHAR2 DEFAULT NULL
    ) IS
    BEGIN
        UPDATE INV_WH_STOCK_BALANCES
           SET quantity           = counted_quantity,
               last_verified_date = SYSDATE,
               remarks            = NVL(p_remarks, 'Reconciled to physical count of ' || counted_quantity),
               updated_at         = SYSDATE
         WHERE balance_id = p_balance_id;

        IF SQL%ROWCOUNT = 0 THEN
            RAISE_APPLICATION_ERROR(-20012, 'Stock balance line not found for ID: ' || p_balance_id);
        END IF;
    END RECONCILE_STOCK;

    FUNCTION GET_ITEM_ZPL (
        p_wh_id      IN NUMBER,
        p_balance_id IN NUMBER DEFAULT NULL,
        p_copies     IN NUMBER DEFAULT 1
    ) RETURN CLOB IS
        v_out         CLOB;
        v_code        VARCHAR2(100);
        v_desc        VARCHAR2(500);
        v_part        VARCHAR2(100);
        v_mfr         VARCHAR2(200);
        v_uom         VARCHAR2(100);
        v_loc_info    VARCHAR2(500);
        v_barcode_val VARCHAR2(100);
        v_single_zpl  VARCHAR2(4000);
        v_copies      NUMBER := NVL(p_copies, 1);
    BEGIN
        BEGIN
            SELECT TO_CHAR(m.material_code),
                   NVL(m.short_description, m.description),
                   m.part_no,
                   m.manufacturer,
                   uom.unit_of_measurement
              INTO v_code, v_desc, v_part, v_mfr, v_uom
              FROM INV_WH_MASTER_DATA m
              LEFT JOIN INV_WH_UNIT_OF_MEASUREMENT_LKP uom ON uom.unit_of_measurement_id = m.unit_of_measurement_id
             WHERE m.wh_id = p_wh_id;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                SELECT TO_CHAR(m.material_code),
                       NVL(m.short_description, m.description),
                       m.part_no,
                       m.manufacturer,
                       uom.unit_of_measurement
                  INTO v_code, v_desc, v_part, v_mfr, v_uom
                  FROM INV_WH_MASTER_DATA m
                  LEFT JOIN INV_WH_UNIT_OF_MEASUREMENT_LKP uom ON uom.unit_of_measurement_id = m.unit_of_measurement_id
                 WHERE m.material_code = TO_CHAR(p_wh_id);
        END;

        IF p_balance_id IS NOT NULL THEN
            BEGIN
                SELECT 'WH: ' || NVL(w.warehouse_name, 'N/A') || ' | Loc: ' || NVL(l.location_name, 'N/A')
                  INTO v_loc_info
                  FROM INV_WH_STOCK_BALANCES b
                  LEFT JOIN INV_WH_WAREHOUSE_LOOKUP w ON w.warehouse_id = b.warehouse_id
                  LEFT JOIN INV_WH_LOCATION_LOOKUP l ON l.location_id = b.location_id
                 WHERE b.balance_id = p_balance_id;
            EXCEPTION
                WHEN NO_DATA_FOUND THEN
                    v_loc_info := 'N/A';
            END;
            v_barcode_val := 'WH-' || v_code || '-' || p_balance_id;
        ELSE
            v_loc_info := 'GENERAL WAREHOUSE';
            v_barcode_val := 'WH-' || v_code;
        END IF;

        v_single_zpl := '^XA' || CHR(10) ||
                        '^PW400' || CHR(10) ||
                        '^LL200' || CHR(10) ||
                        '^LS0' || CHR(10) ||
                        '^FO15,12^A0N,20,20^FDEPROM WAREHOUSE^FS' || CHR(10) ||
                        '^FO15,35^A0N,17,17^FD' || SUBSTR(v_desc, 1, 30) || '^FS' || CHR(10) ||
                        '^FO15,55^A0N,15,15^FD' || SUBSTR(v_loc_info, 1, 32) || '^FS' || CHR(10) ||
                        '^FO15,74^A0N,15,15^FDPart: ' || SUBSTR(NVL(v_part, 'N/A'), 1, 14) || ' | UOM: ' || NVL(v_uom, 'EA') || '^FS' || CHR(10) ||
                        '^FO10,95^BY2,2,65^BCN,65,Y,N,N,A^FD' || v_barcode_val || '^FS' || CHR(10) ||
                        '^XZ' || CHR(10);

        DBMS_LOB.CREATETEMPORARY(v_out, TRUE);
        FOR i IN 1..v_copies LOOP
            DBMS_LOB.WRITEAPPEND(v_out, LENGTH(v_single_zpl), v_single_zpl);
        END LOOP;

        RETURN v_out;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            RETURN '^XA^PW400^LL200^FO15,50^A0N,25,25^FDITEM NOT FOUND^FS^XZ';
    END GET_ITEM_ZPL;

END INV_WH_PKG;
/
