
  CREATE OR REPLACE EDITIONABLE PACKAGE BODY "HQ_ELEVATED"."APPROVAL_PKG" IS

   /* Helper: Insert one approval row */
   PROCEDURE insert_approval (
       p_emp_number        IN NUMBER,
       p_request_type_id   IN NUMBER,
       p_approver          IN VARCHAR2,
       p_seq               IN NUMBER,
       p_is_mandatory      IN VARCHAR2,
       p_type              IN VARCHAR2,
       p_group_name        IN VARCHAR2,
       p_group_id          IN NUMBER,
       p_user              IN VARCHAR2
   ) IS
   BEGIN
      INSERT INTO central.APR_APPROVAL_RESULTS_CUST_F (
          emp_number, request_type_id, approver, approval_sequence,
          is_mandatory, approve_type, approval_group_name,
          approver_desc, approval_group_id, last_updated_by, last_updated_date
      ) VALUES (
          p_emp_number, p_request_type_id, p_approver, p_seq,
          p_is_mandatory, p_type, p_group_name,
          NULL, p_group_id, p_user, SYSDATE
      );
   END insert_approval;

   PROCEDURE process_employee_requests (
       p_emp_numbers   IN VARCHAR2,
       p_site_code     IN NUMBER,
       p_approver1     IN NUMBER,
       p_approver2     IN NUMBER,
       p_fyi_list      IN VARCHAR2,
       p_app_user      IN VARCHAR2
   ) IS
      /* نفس ليست الأنواع بالترتيب */
      TYPE request_type_list IS TABLE OF NUMBER;
      l_request_types  request_type_list := request_type_list(59, 61, 72, 76, 121, 107, 35);

      /* Counters وحالة عامة */
      tens_counter      NUMBER := 0;
      seq               NUMBER := 0;
      current_request_type NUMBER;

      /* Approvers & Groups زي الأصلي (نفس الداتا تايب) */
      GM_public_relation       VARCHAR2(50);
      DEP_GM_public_relation   VARCHAR2(99);

      GM_training              VARCHAR2(50);
      GM_training_FYI          VARCHAR2(50);
      DEP_GM_training          VARCHAR2(99);

      DEP_MANAGER              VARCHAR2(99);
      First_Approval_To_Ceo    VARCHAR2(99);

   BEGIN
      -------------------------------------------------------------------
      -- Static approvers (نفس الـ SELECTs بالظبط)

      -------------------------------------------------------------------
      SELECT approver, approval_group_name
        INTO GM_public_relation, DEP_GM_public_relation
        FROM central.APR_STATIC_APPROVERS
       WHERE approver_id = '14';

      IF p_site_code = 121 THEN
         SELECT approver INTO GM_training     FROM central.APR_STATIC_APPROVERS WHERE approver_id = '141';
         SELECT approver INTO GM_training_FYI FROM central.APR_STATIC_APPROVERS WHERE approver_id = '161';
      ELSE
         SELECT approver INTO GM_training     FROM central.APR_STATIC_APPROVERS WHERE approver_id = '5';
      END IF;

      SELECT approval_group_name
        INTO DEP_GM_training
        FROM central.APR_STATIC_APPROVERS
       WHERE approver_id = '5';

      SELECT APPROVAL_GROUP_NAME
        INTO DEP_MANAGER
        FROM central.APR_APPROVAL_GROUPS
       WHERE APPROVAL_GROUP_ID = '42';

      SELECT APPROVAL_GROUP_NAME
        INTO First_Approval_To_Ceo
        FROM central.APR_APPROVAL_GROUPS
       WHERE APPROVAL_GROUP_ID = '41';

      -------------------------------------------------------------------
      -- Loop on employee numbers (نفس split)
      -------------------------------------------------------------------
      FOR c IN (SELECT column_value AS id
                  FROM TABLE(apex_string.split(p_emp_numbers, ':'))) LOOP

         -- حذف أي نتائج قديمة
         DELETE FROM central.APR_APPROVAL_RESULTS_CUST_F
          WHERE EMP_NUMBER = c.id;

         ----------------------------------------------------------------
         -- اللوب الرئيسي على أنواع الطلبات (زي الأصلي)
         ----------------------------------------------------------------
         FOR i IN 1..l_request_types.COUNT LOOP
            seq := 0;
            current_request_type := l_request_types(i);

            -- مدير الإدارة للأنواع (59, 61, 72)
            IF current_request_type IN (59, 61, 72) THEN
               seq := seq + 1;
               insert_approval(
                  p_emp_number      => c.id,
                  p_request_type_id => current_request_type,
                  p_approver        => NVL(p_approver1, -1),
                  p_seq             => seq,
                  p_is_mandatory    => 'Yes',
                  p_type            => 'FYA',
                  p_group_name      => DEP_MANAGER,
                  p_group_id        => 41,
                  p_user            => p_app_user
               );
            END IF;

            -- Approval 2 (منطِق 121 الخاص)
            seq := seq + 1;
            IF current_request_type = 121 THEN
               IF p_site_code = 121 THEN
                  /* أول واحدة: CEO FYA */
                  seq := seq + 1;
                  insert_approval(
                     c.id, current_request_type, NVL(p_approver2, -1), seq,
                     'Yes', 'FYA', First_Approval_To_Ceo, 41, p_app_user
                  );

                  /* تاني واحدة: FYI GM_training_FYI */
                  seq := seq + 1;
                  insert_approval(
                     c.id, current_request_type, GM_training_FYI, seq,
                     'Yes', 'FYI', First_Approval_To_Ceo, 41, p_app_user
                  );
               ELSE
                  /* مواقع غير 121: CEO FYA مرة واحدة */
                  seq := seq + 1;
                  insert_approval(
                     c.id, current_request_type, NVL(p_approver2, -1), seq,
                     'Yes', 'FYA', First_Approval_To_Ceo, 41, p_app_user
                  );
               END IF;
            END IF;

            /* لو مش 121: إدراج Approval2 (نفس سلوك الأصلي بدون زيادة seq) */
            IF current_request_type <> 121 THEN
               insert_approval(
                  c.id, current_request_type, NVL(p_approver2, -1), seq,
                  'Yes', 'FYA', First_Approval_To_Ceo, 41, p_app_user
               );
            END IF;

            -- FYIs من الآيتم
            IF p_fyi_list IS NOT NULL THEN
               tens_counter := 0;
               FOR f IN (SELECT column_value AS fyi
                           FROM TABLE(apex_string.split(p_fyi_list, ':'))) LOOP
                  tens_counter := tens_counter + 10;
                  insert_approval(
                     c.id, current_request_type, f.fyi, tens_counter,
                     'No', 'FYI', First_Approval_To_Ceo, 42, p_app_user
                  );
               END LOOP;
            END IF;
         END LOOP; -- end main loop

         ----------------------------------------------------------------
         -- لوب إضافي للأنواع الخاصة (نفسًا للأصلي بالترتيب)
         ----------------------------------------------------------------
         FOR i IN 1..l_request_types.COUNT LOOP
            current_request_type := l_request_types(i);

            IF current_request_type = 121 THEN
               /* إدراج GM_training FYA بمجموعة تدريب وبدون group_id */
               insert_approval(
                  c.id, 121, GM_training, seq,
                  'Yes', 'FYA', DEP_GM_training, NULL, p_app_user
               );

            ELSIF current_request_type = 107 THEN
               /* FYI على 107 و 35 لنفس GM_public_relation وبـ seq+10 وبدون group_id */
               insert_approval(
                  c.id, 107, GM_public_relation, seq+10,
                  'No', 'FYI', DEP_GM_public_relation, NULL, p_app_user
               );

               insert_approval(
                  c.id, 35, GM_public_relation, seq+10,
                  'No', 'FYI', DEP_GM_public_relation, NULL, p_app_user
               );
            END IF;
         END LOOP;

         -- تعديل is_mandatory لو الـ approver = -1
         UPDATE central.APR_APPROVAL_RESULTS_CUST_F
            SET is_mandatory = 'No'
          WHERE approver = '-1'
            AND emp_number = c.id;

      END LOOP; -- employees

      COMMIT;

   EXCEPTION
      WHEN OTHERS THEN
         -- ممكن تضيف جدول لوجينج هنا لو عندكم (مثال):
         -- INSERT INTO central.approval_errors(log_dt, err_msg) VALUES (SYSDATE, SQLERRM);
         ROLLBACK;
         RAISE;
   END process_employee_requests;



    PROCEDURE create_next_approval_log (
        p_request_id      IN NUMBER,
        p_request_source  IN VARCHAR2,
        p_request_type_id IN NUMBER,
        p_emp_id          IN NUMBER
    ) IS
    BEGIN
        -- ضع منطق إنشاء سجل الاعتماد التالي هنا
        NULL;
    END create_next_approval_log;


END approval_pkg;
/
