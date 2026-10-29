
  CREATE OR REPLACE EDITIONABLE FUNCTION "EPROMHQ"."GET_CITY_NAME" (p_city_id IN NUMBER) RETURN VARCHAR2 IS
   v_city_name VARCHAR2(100);
BEGIN
   CASE p_city_id
      WHEN 7 THEN v_city_name := 'Cairo';
      WHEN 9 THEN v_city_name := 'Suez';
      WHEN 10 THEN v_city_name := 'Alexandria';
      WHEN 17 THEN v_city_name := 'Matrouh';
      WHEN 19 THEN v_city_name := 'Other';
      WHEN 21 THEN v_city_name := 'Ain Sokhna';
      ELSE v_city_name := 'Unknown City'; -- Handle unknown IDs
   END CASE;
   RETURN v_city_name;
END;
/
