
  CREATE OR REPLACE EDITIONABLE FUNCTION "EPROMHQ"."INV_ZPL_SIMPLE" (
    p_line1   IN VARCHAR2,   -- First text line (e.g. model info)
    p_line2   IN VARCHAR2,   -- Second text line (e.g. Serial: ...)
    p_barcode IN VARCHAR2,   -- Data for the barcode (e.g. "010201-000001")
    p_show_text_under_barcode IN VARCHAR2 DEFAULT 'N'  -- 'Y' = show text under barcode, 'N' = hide it
) RETURN VARCHAR2 AS

    v_bc_params VARCHAR2(30);

BEGIN
    -- Build the ^BC parameters
    -- Format: ^BCo,h,f,g,e,m
    -- We use: N (normal), height from ^BY, f = show text?, g = below (N), e=N, m=N
    IF UPPER(p_show_text_under_barcode) = 'Y' THEN
        v_bc_params := '^BCN,70,Y,N,N,N';   -- show interpretation line below
    ELSE
        v_bc_params := '^BCN,70,N,N,N,N';   -- hide interpretation line completely
    END IF;

    RETURN '^XA' ||
           -- Line 1
           '^FO20,20^A0,23,23^FD' || p_line1 || '^FS' ||
           -- Line 2
           '^FO20,50^A0,21,21^FD' || p_line2 || '^FS' ||
           -- Barcode section
           '^FO20,85^BY2,2,70' || v_bc_params || '^FD' || p_barcode || '^FS' ||
           '^XZ';
END INV_ZPL_SIMPLE;
/
