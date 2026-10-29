
  CREATE OR REPLACE EDITIONABLE PACKAGE "EPROMHQ"."INV_WH_PKG" AS
    /*
     * Package:     INV_WH_PKG
     * Purpose:     Unified Warehouse Inventory & Multi-Location Stock Management
     * Enhancement: Multi-Criteria RESET_COUNTS with Backward Compatibility
     */

    PROCEDURE RECEIVE_STOCK (
        p_wh_id             IN NUMBER,
        p_client_id         IN NUMBER,
        p_project_id        IN NUMBER,
        p_location_id       IN NUMBER,
        p_warehouse_id      IN NUMBER DEFAULT NULL,
        p_quantity          IN NUMBER,
        p_remarks           IN VARCHAR2 DEFAULT NULL
    );

    PROCEDURE ADJUST_STOCK (
        p_balance_id        IN NUMBER,
        p_new_quantity      IN NUMBER,
        p_remarks           IN VARCHAR2 DEFAULT NULL
    );

    PROCEDURE TRANSFER_STOCK (
        p_from_balance_id   IN NUMBER,
        p_to_client_id      IN NUMBER,
        p_to_project_id     IN NUMBER,
        p_to_location_id    IN NUMBER,
        p_to_warehouse_id   IN NUMBER DEFAULT NULL,
        p_quantity          IN NUMBER,
        p_remarks           IN VARCHAR2 DEFAULT NULL
    );

    PROCEDURE INCREMENT_COUNT (
        p_balance_id    IN NUMBER,
        p_qty           IN NUMBER DEFAULT 1,
        o_new_count     OUT NUMBER
    );

    -- Multi-criteria reset procedure for Admin Page
    PROCEDURE RESET_COUNTS (
        p_warehouse_id  IN NUMBER DEFAULT NULL,
        p_location_id   IN NUMBER DEFAULT NULL,
        p_client_id     IN NUMBER DEFAULT NULL,
        p_project_id    IN NUMBER DEFAULT NULL,
        p_wh_id         IN NUMBER DEFAULT NULL,
        o_reset_count   OUT NUMBER
    );

    -- Backward compatibility wrapper for existing Page 300 button call
    PROCEDURE RESET_COUNTS (
        p_warehouse_id  IN NUMBER DEFAULT NULL,
        p_wh_id         IN NUMBER DEFAULT NULL
    );

    PROCEDURE RECONCILE_STOCK (
        p_balance_id    IN NUMBER,
        p_remarks       IN VARCHAR2 DEFAULT NULL
    );

    FUNCTION GET_ITEM_ZPL (
        p_wh_id      IN NUMBER,
        p_balance_id IN NUMBER DEFAULT NULL,
        p_copies     IN NUMBER DEFAULT 1
    ) RETURN CLOB;

END INV_WH_PKG;
/
