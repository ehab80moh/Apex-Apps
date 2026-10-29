
  CREATE OR REPLACE EDITIONABLE FUNCTION "EPROMHQ"."YEAR"
(
  p_date in date
) return number as
begin
  return to_char(p_date,'yyyy');
end year;
/
