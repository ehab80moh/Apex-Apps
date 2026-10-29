
  CREATE OR REPLACE EDITIONABLE FUNCTION "EPROMHQ"."INV_ZPL" (
    p_title  IN VARCHAR2, -- Model Name
    p_man    IN VARCHAR2, -- Manufacturer
    p_type   IN VARCHAR2, -- Category Name
    p_serial IN VARCHAR2, -- Serial Number
    p_def    IN VARCHAR2, -- Definition (Dept + Location + Category)
    p_id     IN VARCHAR2  -- Inventory ID
) RETURN VARCHAR2 AS
BEGIN
    RETURN '^XA' ||
           -- Title (Top)
           '^FO20,25^A0,20,20^FD' || 'EPROM ' || p_title || '^FS' ||
           -- Manufacturer and Type (Below Title)
           '^FO20,50^A0,18,18^FD' || 'Model: ' || p_man || ', Type: ' || p_type || '^FS' ||
           -- Serial Number (Center of Label)
           '^FO20,80^A0,18,19^FDSerial: ' || p_serial || '^FS' ||
           -- Barcode (Bottom Section)
           '^FO20,110^BY2,2,70^BCN,70,Y,N,N^FD' || p_def || '-' || p_id || '^FS' || '^XZ';
END INV_ZPL;


--create or replace FUNCTION "INV_ZPL"
--(
--  p_title in varchar2
--, p_man in varchar2
--, p_type in varchar2
--, p_serial in varchar2
--, p_def in varchar2
--, p_id in varchar2
--) return varchar2 as
--begin
--  return '^XA^FO40,30^PA1,1,1,1^A0,25^FDEPROM '||p_title||'^FS^FO60,60^A1,15^FD'||p_man||' - '||p_type||' - '||p_serial||'^FS^FO70,80^BY2^BCN,80,Y,,,A^FD'||p_def||'-'||p_id||'^FS^XZ';
--end inv_zpl;
/
