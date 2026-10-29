
  CREATE OR REPLACE EDITIONABLE PACKAGE BODY "EPROMHQ"."VAC_PKG" AS
 PROCEDURE vac_generate_blocs (
    p_num_blocs  IN NUMBER,
    p_num_days   IN NUMBER,
    p_start_date IN DATE,
    p_price      IN NUMBER,
    p_unit_id    NUMBER
  ) AS
    v_from        DATE;
    v_to          DATE;
    v_x9          NUMBER(10,2);
    v_x10         NUMBER(10,2);
    v_m9          NUMBER(10,2);
    v_m10         NUMBER(10,2);
    v_base_m9     NUMBER;
    v_base_m10    NUMBER;
    v_total_m9    NUMBER;
    v_total_m10   NUMBER;
    v_base_x10  NUMBER;
     v_base_x9  NUMBER;

  BEGIN
       v_to := p_start_date;

        FOR i IN 1..p_num_blocs LOOP
      v_from := v_to;
      v_to := v_from + p_num_days;
      IF i = p_num_blocs THEN
        v_to := v_to + 1;
      END IF;

      -- حساب x_9 و x_10
      v_x9 := p_price * 0.4;
      v_x10 := p_price * 0.5;

      v_base_x9 := v_x9 / 18;
      v_base_x10 := v_x10 / 18;

      -- m_9 المستوي التاسع
      IF i IN (1,2,3,16,17,18) THEN
        v_m9 := ROUND(v_base_x9 * 0.95, 2);
        v_m10 := ROUND(v_base_x10 * 0.95, 2);
        if i in (18) then
                v_m9 := ROUND(v_base_x9 * 0.90, 2);
        v_m10 := ROUND(v_base_x10 * 0.90, 2);
        end if;
      ELSE
        v_m9 := ROUND((v_x9 - ((v_base_x9 * 0.95 * 5) + (v_base_x9 * 0.90))) / 12, 2);
        v_m10 := ROUND((v_x10 - ((v_base_x10 * 0.95 * 5) + (v_base_x10 * 0.90))) / 12, 2);
      END IF;


      INSERT INTO vac_blocs (
        date_from,
        date_to,
        bloc_price,
        unit_id,
        x_9,
        x_10,
        m_9,
        m_10
      ) VALUES (
        v_from,
        v_to,
        p_price,
        p_unit_id,
        v_x9,
        v_x10,
        v_m9,
        v_m10
      );
    END LOOP;

    COMMIT;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      RAISE;
  END vac_generate_blocs;

  PROCEDURE vac_set_wishes_order (
    p_emp_id  IN VARCHAR2,
    p_trip_id IN NUMBER
  ) AS
    CURSOR cr (
      e VARCHAR2,
      t NUMBER
    ) IS
      SELECT * FROM vac_emp_wishes
      WHERE emp_id = e AND trip_id = t
      ORDER BY ord;

    v_num NUMBER := 1;
  BEGIN
    FOR c IN cr(p_emp_id, p_trip_id) LOOP
      UPDATE vac_emp_wishes
      SET ord = v_num
      WHERE wish_id = c.wish_id;
      v_num := v_num + 1;
    END LOOP;

    COMMIT;
  END vac_set_wishes_order;

  FUNCTION insert_emp_wish (
    p_emp_id  VARCHAR2,
    p_trip_id NUMBER,
    p_bloc_id NUMBER
  ) RETURN NUMBER AS
    v_count NUMBER;
    v_wish_id NUMBER;
  BEGIN
    SELECT COUNT(*) INTO v_count
    FROM vac_emp_wishes
    WHERE emp_id = p_emp_id AND trip_id = p_trip_id;

    INSERT INTO vac_emp_wishes (
      emp_id,
      bloc_id,
      trip_id,
      ord
    ) VALUES (
      p_emp_id,
      p_bloc_id,
      p_trip_id,
      v_count + 1
    )
    RETURNING wish_id INTO v_wish_id;

    COMMIT;
    RETURN v_wish_id;
  EXCEPTION
    WHEN DUP_VAL_ON_INDEX THEN
      RETURN 0;
    WHEN OTHERS THEN
      ROLLBACK;
      RAISE;
  END insert_emp_wish;

  PROCEDURE delete_wish (
    p_wish_id NUMBER
  ) AS
    emp_id VARCHAR2(99);
    trip_id NUMBER;
  BEGIN
    SELECT emp_id, trip_id INTO emp_id, trip_id
    FROM vac_emp_wishes
    WHERE wish_id = p_wish_id;

    DELETE FROM vac_emp_wishes WHERE wish_id = p_wish_id;

    COMMIT;

    vac_set_wishes_order(emp_id, trip_id);
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      RAISE;
  END delete_wish;

END vac_pkg;
/
