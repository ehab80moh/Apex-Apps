
  CREATE OR REPLACE EDITIONABLE FUNCTION "EPROMHQ"."MON"
(
  p_date in date
) return number as
begin
  return to_char(p_date,'mm');
end mon;
/
