
  CREATE OR REPLACE EDITIONABLE PACKAGE "EPROMHQ"."VAC_PKG" AS

  PROCEDURE vac_generate_blocs (
    p_num_blocs  IN NUMBER,
    p_num_days   IN NUMBER,
    p_start_date IN DATE,
    p_price      IN NUMBER,
    p_unit_id    NUMBER
  );

  PROCEDURE vac_set_wishes_order (
    p_emp_id  IN VARCHAR2,
    p_trip_id IN NUMBER
  );

  FUNCTION insert_emp_wish (
    p_emp_id  VARCHAR2,
    p_trip_id NUMBER,
    p_bloc_id NUMBER
  ) RETURN NUMBER;

  PROCEDURE delete_wish (
    p_wish_id NUMBER
  );

END vac_pkg;
/
