
  CREATE OR REPLACE EDITIONABLE FUNCTION "EPROMHQ"."INV_ZPL_BY_ID"
(
  P_INV_ID IN VARCHAR2
) RETURN VARCHAR2 AS
cursor cr is
select * from INV_V_FULL
where inv_id =P_INV_ID;
v_def varchar(99);
-- v_text varchar2(999);
v_serial varchar2(20);
v_out clob ;
BEGIN

for c in cr loop
v_serial := null;--just in case
v_def := LPAD(c.department_id, 2, '0') || LPAD(c.location_id, 2, '0') || LPAD(c.category_id, 2, '0') ;
if (length(c.serial)<=8) then
v_serial := c.serial;
else
v_serial :=substr(c.serial, -8);
end if;
v_out := v_out||  inv_zpl(c.model_name, c.company, c.category_name, v_serial, v_def, lpad(c.inv_id, 6, '0')) ;
end loop;

  RETURN v_out;
END INV_ZPL_BY_ID;
/
