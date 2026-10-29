
  CREATE OR REPLACE EDITIONABLE FUNCTION "EPROMHQ"."INV_WH_CREATE_ITEMS" (
    p_wh_id     IN NUMBER,
    p_quantity  IN NUMBER
) RETURN NUMBER IS
BEGIN
    INV_WH_PKG.RECEIVE_STOCK(
        p_wh_id        => p_wh_id,
        p_client_id    => 21,
        p_project_id   => 18,
        p_location_id  => 10,
        p_warehouse_id => NULL,
        p_quantity     => p_quantity,
        p_remarks      => 'Auto-created via legacy INV_WH_CREATE_ITEMS wrapper'
    );
    RETURN p_quantity;
END INV_WH_CREATE_ITEMS;
/
