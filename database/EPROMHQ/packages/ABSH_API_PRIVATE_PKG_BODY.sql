
  CREATE OR REPLACE EDITIONABLE PACKAGE BODY "EPROMHQ"."ABSH_API_PRIVATE_PKG" AS

   ----------------------------------------------------------------------------------------------------------------------
   FUNCTION GENERATE_JWT(P_USER_ID IN NUMBER) RETURN VARCHAR2 IS
      L_USERNAME VARCHAR2(100);
      L_MOBILE   VARCHAR2(50);
      L_TOKEN    VARCHAR2(4000);
   BEGIN
      -- Load user data
      SELECT NVL(S.REAL_USER_NAME, S.UNIQUE_NAME), S.MOBILE_NO
        INTO L_USERNAME, L_MOBILE
        FROM SM_USER S
       WHERE S.USER_ID = P_USER_ID
         AND S.ROLE_ID = 'INDV_CUSTOMER';

      -- Generate JWT (No APEX_JSON stringify, use simple concatenation)
      L_TOKEN := APEX_JWT.ENCODE(P_ISS           => C_ISSUER,
                                 P_SUB           => P_USER_ID,
                                 P_AUD           => C_USER_ROLE,
                                 P_EXP_SEC       => C_JWT_EXPIRY_SEC,
                                 P_SIGNATURE_KEY => C_SECRET_KEY,
                                 P_OTHER_CLAIMS  => '"user_id": ' || P_USER_ID || ',"mobile": "' || L_MOBILE || '"');

      RETURN L_TOKEN;

   EXCEPTION
      WHEN NO_DATA_FOUND THEN
         RAISE_APPLICATION_ERROR(-20010, 'ERR_USER_NOT_FOUND');
   END GENERATE_JWT;
   --------------------------------------------------------------------------------------------------------------------------

   FUNCTION VALIDATE_JWT_AND_GET_USER_ID
   (
      P_JWT               IN VARCHAR2
     ,P_ALLOW_DEACTIVATED IN BOOLEAN DEFAULT FALSE
   ) RETURN NUMBER IS
      L_TOKEN        APEX_JWT.T_TOKEN;
      L_PAYLOAD_JSON JSON_OBJECT_T;
      L_USER_ID      NUMBER;
   BEGIN
      BEGIN
         -- Decode JWT
         L_TOKEN := APEX_JWT.DECODE(P_VALUE => P_JWT, P_SIGNATURE_KEY => C_SECRET_KEY);

         -- Validate standard claims
         APEX_JWT.VALIDATE(P_TOKEN => L_TOKEN, P_ISS => C_ISSUER, P_AUD => C_USER_ROLE);

         -- Parse payload
         L_PAYLOAD_JSON := JSON_OBJECT_T.PARSE(L_TOKEN.PAYLOAD);

         -- Extract user_id (stored in SUB)
         L_USER_ID := L_PAYLOAD_JSON.GET_NUMBER('sub');

      EXCEPTION
         WHEN OTHERS THEN
            RAISE_APPLICATION_ERROR(-20011, 'ERR_INVALID_OR_EXPIRED_JWT');
      END;
      --  check user is active via DELETED_FLAG, UNIQUE_NAME AND EXISTS
      ABSH_API_UTIL_PKG.VALIDATE_USER_EXISTS(P_USER_ID => L_USER_ID, P_ALLOW_DEACTIVATED => P_ALLOW_DEACTIVATED);

      RETURN L_USER_ID;

   END VALIDATE_JWT_AND_GET_USER_ID;

   ------------------------------------------------------------------
   -- ADD_ADDRESS
   ------------------------------------------------------------------
   FUNCTION ADD_ADDRESS(P_PAYLOAD_JSON IN CLOB) RETURN NUMBER IS
      L_USER_ID          NUMBER;
      L_CUSTOMER_ID      NUMBER;
      L_POT_CUST_ID      NUMBER;
      L_ADDRESS_ID       NUMBER;
      L_DATA             CLOB;
      L_LANG             VARCHAR2(10);
      L_TOKEN            VARCHAR2(4000);
      L_NAME             VARCHAR2(100);
      L_CITY_ID          NUMBER;
      L_STATE            VARCHAR2(100);
      L_DETAILS          VARCHAR2(200);
      L_IS_DEFAULT       NUMBER;
      L_LATITUDE         NUMBER;
      L_LONGITUDE        NUMBER;
      L_CUST_ID          NUMBER;
      L_CUST_TYPE        VARCHAR2(20);
      L_ADDITIONAL_PHONE VARCHAR2(99);
      L_ADDRESS_TYPE     VARCHAR2(99);
   BEGIN
      L_TOKEN            := ABSH_API_UTIL_PKG.GET_BEARER_TOKEN;
      L_NAME             := JSON_VALUE(P_PAYLOAD_JSON, '$.name');
      L_CITY_ID          := JSON_VALUE(P_PAYLOAD_JSON, '$.city_id' RETURNING NUMBER);
      L_STATE            := JSON_VALUE(P_PAYLOAD_JSON, '$.state');
      L_DETAILS          := JSON_VALUE(P_PAYLOAD_JSON, '$.details');
      L_IS_DEFAULT       := JSON_VALUE(P_PAYLOAD_JSON, '$.is_default' RETURNING NUMBER);
      L_LATITUDE         := JSON_VALUE(P_PAYLOAD_JSON, '$.latitude' RETURNING NUMBER);
      L_LONGITUDE        := JSON_VALUE(P_PAYLOAD_JSON, '$.longitude' RETURNING NUMBER);
      L_LANG             := ABSH_API_UTIL_PKG.RESOLVE_LANG(JSON_VALUE(P_PAYLOAD_JSON, '$.acceptLanguage'));
      L_ADDITIONAL_PHONE := JSON_VALUE(P_PAYLOAD_JSON, '$.additionalPhone');
      L_ADDRESS_TYPE     := JSON_VALUE(P_PAYLOAD_JSON, '$.addressType');

      ABSH_API_UTIL_PKG.VALIDATE_API_KEY(ABSH_API_UTIL_PKG.GET_APIKEY);

      IF L_TOKEN IS NULL THEN
         ABSH_API_UTIL_PKG.ERROR_RESPONSE(400, 'ERR_MISSING_PARAM', L_LANG, APEX_T_VARCHAR2('NAME', 'token'));
         RETURN 400;
      END IF;

      IF L_NAME IS NULL THEN
         ABSH_API_UTIL_PKG.ERROR_RESPONSE(400, 'ERR_MISSING_PARAM', L_LANG, APEX_T_VARCHAR2('NAME', 'name'));
         RETURN 400;
      END IF;

      IF L_DETAILS IS NULL THEN
         ABSH_API_UTIL_PKG.ERROR_RESPONSE(400, 'ERR_MISSING_PARAM', L_LANG, APEX_T_VARCHAR2('NAME', 'details'));
         RETURN 400;
      END IF;

      IF L_LATITUDE IS NULL THEN
         ABSH_API_UTIL_PKG.ERROR_RESPONSE(400, 'ERR_MISSING_PARAM', L_LANG, APEX_T_VARCHAR2('NAME', 'latitude'));
         RETURN 400;
      END IF;
      IF L_LONGITUDE IS NULL THEN
         ABSH_API_UTIL_PKG.ERROR_RESPONSE(400, 'ERR_MISSING_PARAM', L_LANG, APEX_T_VARCHAR2('NAME', 'longitude'));
         RETURN 400;
      END IF;

      L_USER_ID := ABSH_API_PRIVATE_PKG.VALIDATE_JWT_AND_GET_USER_ID(L_TOKEN);

      ABSH_API_UTIL_PKG.GET_CUSTOMER_INFO(L_USER_ID, L_CUST_ID, L_CUST_TYPE);
      IF L_CUST_TYPE = 'CUSTOMER' THEN
         L_CUSTOMER_ID := L_CUST_ID;
      ELSIF L_CUST_TYPE = 'POTENTIAL' THEN
         L_POT_CUST_ID := L_CUST_ID;
      END IF;

      IF L_CUSTOMER_ID IS NULL AND L_POT_CUST_ID IS NULL THEN
         ABSH_API_UTIL_PKG.ERROR_RESPONSE(403, 'ERR_USER_NOT_FOUND', L_LANG);
         RETURN 403;
      END IF;

      IF L_ADDITIONAL_PHONE IS NOT NULL THEN
         L_ADDITIONAL_PHONE := ABSH_API_UTIL_PKG.NORMALIZE_SA_MOBILE(L_ADDITIONAL_PHONE);
      END IF;

      ABSH_BUSINESS_PRIVATE_PKG.ADD_ADDRESS(
         P_CUSTOMER_ID      => L_CUSTOMER_ID,
         P_POT_CUST_ID      => L_POT_CUST_ID,
         P_ADDRESS_TYPE     => L_ADDRESS_TYPE,
         P_NAME             => L_NAME,
         P_DETAILS          => L_DETAILS,
         P_STATE            => L_STATE,
         P_CITY_ID          => L_CITY_ID,
         P_IS_DEFAULT       => L_IS_DEFAULT,
         P_LATITUDE         => L_LATITUDE,
         P_LONGITUDE        => L_LONGITUDE,
         P_ADDITIONAL_PHONE => L_ADDITIONAL_PHONE,
         P_ADDRESS_ID       => L_ADDRESS_ID
      );

      SELECT JSON_OBJECT('address_id' VALUE ADDRESS_ID,
                         'address_name' VALUE ADDRESS_NAME,
                         'street' VALUE STREET,
                         'state' VALUE STATE,
                         'city_id' VALUE CITY_ID,
                         'is_default' VALUE IS_DEFAULT,
                         'latitude' VALUE LATITUDE,
                         'longitude' VALUE LONGITUDE,
                         'additionalPhone' VALUE ADDITIONAL_PHONE NULL ON NULL RETURNING CLOB)
        INTO L_DATA
        FROM ABSH_CUSTOMER_ADDRESSES
       WHERE ADDRESS_ID = L_ADDRESS_ID;

      COMMIT;
      ABSH_API_UTIL_PKG.SUCCESS_RESPONSE(P_MESSAGE_KEY => 'ADDRESS_ADDED', P_LANG => L_LANG, P_DATA => L_DATA);
      RETURN 200;

   EXCEPTION
      WHEN OTHERS THEN
         ROLLBACK;
         ABSH_API_UTIL_PKG.LOG_ERROR(P_ERROR_MESSAGE => SQLERRM,
                                     P_ERROR_CODE    => SQLCODE,
                                     P_ERROR_STACK   => DBMS_UTILITY.FORMAT_ERROR_BACKTRACE,
                                     P_CALLING_PROC  => 'ABSH_API_PRIVATE_PKG.ADD_ADDRESS',
                                     P_TABLE_NAME    => 'ABSH_CUSTOMER_ADDRESSES');

         ABSH_API_UTIL_PKG.ERROR_RESPONSE(500, 'ERR_INTERNAL', L_LANG);
         RETURN 500;
   END ADD_ADDRESS;

   ------------------------------------------------------------------
   -- UPDATE_ADDRESS
   ------------------------------------------------------------------
   FUNCTION UPDATE_ADDRESS(P_PAYLOAD_JSON IN CLOB) RETURN NUMBER IS
      L_USER_ID          NUMBER;
      L_CUSTOMER_ID      NUMBER;
      L_POT_CUST_ID      NUMBER;
      L_DATA             CLOB;
      L_LANG             VARCHAR2(10);
      L_TOKEN            VARCHAR2(4000);
      L_ID               NUMBER;
      L_NAME             VARCHAR2(100);
      L_CITY_ID          NUMBER;
      L_STATE            VARCHAR2(100);
      L_DETAILS          VARCHAR2(200);
      L_IS_DEFAULT       NUMBER;
      L_LATITUDE         NUMBER;
      L_LONGITUDE        NUMBER;
      L_CUST_ID          NUMBER;
      L_CUST_TYPE        VARCHAR2(20);
      L_ADDITIONAL_PHONE VARCHAR2(99);
   BEGIN
      L_TOKEN            := ABSH_API_UTIL_PKG.GET_BEARER_TOKEN;
      L_ID               := JSON_VALUE(P_PAYLOAD_JSON, '$.id' RETURNING NUMBER);
      L_NAME             := JSON_VALUE(P_PAYLOAD_JSON, '$.name');
      L_CITY_ID          := JSON_VALUE(P_PAYLOAD_JSON, '$.city_id' RETURNING NUMBER);
      L_STATE            := JSON_VALUE(P_PAYLOAD_JSON, '$.state');
      L_DETAILS          := JSON_VALUE(P_PAYLOAD_JSON, '$.details');
      L_IS_DEFAULT       := JSON_VALUE(P_PAYLOAD_JSON, '$.is_default' RETURNING NUMBER);
      L_LATITUDE         := JSON_VALUE(P_PAYLOAD_JSON, '$.latitude' RETURNING NUMBER);
      L_LONGITUDE        := JSON_VALUE(P_PAYLOAD_JSON, '$.longitude' RETURNING NUMBER);
      L_LANG             := ABSH_API_UTIL_PKG.RESOLVE_LANG(JSON_VALUE(P_PAYLOAD_JSON, '$.acceptLanguage'));
      L_ADDITIONAL_PHONE := JSON_VALUE(P_PAYLOAD_JSON, '$.additionalPhone');

      ABSH_API_UTIL_PKG.VALIDATE_API_KEY(ABSH_API_UTIL_PKG.GET_APIKEY);

      IF L_TOKEN IS NULL THEN
         ABSH_API_UTIL_PKG.ERROR_RESPONSE(400, 'ERR_MISSING_PARAM', L_LANG, APEX_T_VARCHAR2('NAME', 'token'));
         RETURN 400;
      END IF;

      IF L_ID IS NULL THEN
         ABSH_API_UTIL_PKG.ERROR_RESPONSE(400, 'ERR_MISSING_PARAM', L_LANG, APEX_T_VARCHAR2('NAME', 'id'));
         RETURN 400;
      END IF;

      IF L_LATITUDE IS NULL THEN
         ABSH_API_UTIL_PKG.ERROR_RESPONSE(400, 'ERR_MISSING_PARAM', L_LANG, APEX_T_VARCHAR2('NAME', 'latitude'));
         RETURN 400;
      END IF;
      IF L_LONGITUDE IS NULL THEN
         ABSH_API_UTIL_PKG.ERROR_RESPONSE(400, 'ERR_MISSING_PARAM', L_LANG, APEX_T_VARCHAR2('NAME', 'longitude'));
         RETURN 400;
      END IF;

      L_USER_ID := ABSH_API_PRIVATE_PKG.VALIDATE_JWT_AND_GET_USER_ID(L_TOKEN);

      ABSH_API_UTIL_PKG.GET_CUSTOMER_INFO(L_USER_ID, L_CUST_ID, L_CUST_TYPE);
      IF L_CUST_TYPE = 'CUSTOMER' THEN
         L_CUSTOMER_ID := L_CUST_ID;
      ELSIF L_CUST_TYPE = 'POTENTIAL' THEN
         L_POT_CUST_ID := L_CUST_ID;
      END IF;

      IF L_CUSTOMER_ID IS NULL AND L_POT_CUST_ID IS NULL THEN
         ABSH_API_UTIL_PKG.ERROR_RESPONSE(403, 'ERR_USER_NOT_FOUND', L_LANG);
         RETURN 403;
      END IF;

      IF L_ADDITIONAL_PHONE IS NOT NULL THEN
         L_ADDITIONAL_PHONE := ABSH_API_UTIL_PKG.NORMALIZE_SA_MOBILE(L_ADDITIONAL_PHONE);
      END IF;

      ABSH_BUSINESS_PRIVATE_PKG.UPDATE_ADDRESS(
         P_ADDRESS_ID       => L_ID,
         P_CUSTOMER_ID      => L_CUSTOMER_ID,
         P_POT_CUST_ID      => L_POT_CUST_ID,
         P_NAME             => L_NAME,
         P_DETAILS          => L_DETAILS,
         P_STATE            => L_STATE,
         P_CITY_ID          => L_CITY_ID,
         P_IS_DEFAULT       => L_IS_DEFAULT,
         P_LATITUDE         => L_LATITUDE,
         P_LONGITUDE        => L_LONGITUDE,
         P_ADDITIONAL_PHONE => L_ADDITIONAL_PHONE
      );

      SELECT JSON_OBJECT('address_id' VALUE ADDRESS_ID,
                         'address_name' VALUE ADDRESS_NAME,
                         'street' VALUE STREET,
                         'state' VALUE STATE,
                         'city_id' VALUE CITY_ID,
                         'is_default' VALUE IS_DEFAULT,
                         'latitude' VALUE LATITUDE,
                         'longitude' VALUE LONGITUDE,
                         'additionalPhone' VALUE ADDITIONAL_PHONE NULL ON NULL RETURNING CLOB)
        INTO L_DATA
        FROM ABSH_CUSTOMER_ADDRESSES
       WHERE ADDRESS_ID = L_ID;

      COMMIT;
      ABSH_API_UTIL_PKG.SUCCESS_RESPONSE(P_MESSAGE_KEY => 'ADDRESS_UPDATED', P_LANG => L_LANG, P_DATA => L_DATA);
      RETURN 200;

   EXCEPTION
      WHEN OTHERS THEN
         ROLLBACK;
         IF SQLCODE = -20002 OR SQLERRM LIKE '%ERR_ADDRESS_NOT_FOUND%' THEN
            ABSH_API_UTIL_PKG.ERROR_RESPONSE(403, 'ERR_ADDRESS_NOT_FOUND', L_LANG);
            RETURN 403;
         ELSE
            ABSH_API_UTIL_PKG.LOG_ERROR(P_ERROR_MESSAGE => SQLERRM,
                                        P_ERROR_CODE    => SQLCODE,
                                        P_ERROR_STACK   => DBMS_UTILITY.FORMAT_ERROR_BACKTRACE,
                                        P_CALLING_PROC  => 'ABSH_API_PRIVATE_PKG.UPDATE_ADDRESS',
                                        P_TABLE_NAME    => 'ABSH_CUSTOMER_ADDRESSES');
            ABSH_API_UTIL_PKG.ERROR_RESPONSE(500, 'ERR_INTERNAL', L_LANG);
            RETURN 500;
         END IF;
   END UPDATE_ADDRESS;

   ------------------------------------------------------------------
   -- DELETE_ADDRESS
   ------------------------------------------------------------------
   FUNCTION DELETE_ADDRESS(P_PAYLOAD_JSON IN CLOB) RETURN NUMBER IS
      L_USER_ID     NUMBER;
      L_CUSTOMER_ID NUMBER;
      L_POT_CUST_ID NUMBER;
      L_LANG        VARCHAR2(10);
      L_TOKEN       VARCHAR2(4000);
      L_ID          NUMBER;
      L_CUST_ID     NUMBER;
      L_CUST_TYPE   VARCHAR2(20);
      L_DATA        CLOB;
   BEGIN
      IF P_PAYLOAD_JSON IS NULL OR LENGTH(TRIM(P_PAYLOAD_JSON)) = 0 THEN
         ABSH_API_UTIL_PKG.ERROR_RESPONSE(400, 'ERR_MISSING_PARAM', C_DEFAULT_LANG, APEX_T_VARCHAR2('NAME', 'body'));
         RETURN 400;
      END IF;

      L_LANG  := ABSH_API_UTIL_PKG.RESOLVE_LANG(JSON_VALUE(P_PAYLOAD_JSON, '$.acceptLanguage'));
      L_TOKEN := ABSH_API_UTIL_PKG.GET_BEARER_TOKEN;
      L_ID    := JSON_VALUE(P_PAYLOAD_JSON, '$.id' RETURNING NUMBER);

      ABSH_API_UTIL_PKG.VALIDATE_API_KEY(ABSH_API_UTIL_PKG.GET_APIKEY);

      IF L_TOKEN IS NULL THEN
         ABSH_API_UTIL_PKG.ERROR_RESPONSE(400, 'ERR_MISSING_PARAM', L_LANG, APEX_T_VARCHAR2('NAME', 'token'));
         RETURN 400;
      END IF;

      IF L_ID IS NULL THEN
         ABSH_API_UTIL_PKG.ERROR_RESPONSE(400, 'ERR_MISSING_PARAM', L_LANG, APEX_T_VARCHAR2('NAME', 'id'));
         RETURN 400;
      END IF;

      L_USER_ID := ABSH_API_PRIVATE_PKG.VALIDATE_JWT_AND_GET_USER_ID(L_TOKEN);

      ABSH_API_UTIL_PKG.GET_CUSTOMER_INFO(L_USER_ID, L_CUST_ID, L_CUST_TYPE);
      IF L_CUST_TYPE = 'CUSTOMER' THEN
         L_CUSTOMER_ID := L_CUST_ID;
      ELSIF L_CUST_TYPE = 'POTENTIAL' THEN
         L_POT_CUST_ID := L_CUST_ID;
      END IF;

      IF L_CUSTOMER_ID IS NULL AND L_POT_CUST_ID IS NULL THEN
         ABSH_API_UTIL_PKG.ERROR_RESPONSE(403, 'ERR_USER_NOT_FOUND', L_LANG);
         RETURN 403;
      END IF;

      ABSH_BUSINESS_PRIVATE_PKG.DELETE_ADDRESS(
         P_ADDRESS_ID  => L_ID,
         P_CUSTOMER_ID => L_CUSTOMER_ID,
         P_POT_CUST_ID => L_POT_CUST_ID
      );

      COMMIT;
      ABSH_API_UTIL_PKG.SUCCESS_RESPONSE(P_MESSAGE_KEY => 'ADDRESS_DELETED', P_LANG => L_LANG, P_DATA => L_DATA);
      RETURN 200;

   EXCEPTION
      WHEN OTHERS THEN
         ROLLBACK;
         IF SQLCODE = -20002 OR SQLERRM LIKE '%ERR_ADDRESS_NOT_FOUND%' THEN
            ABSH_API_UTIL_PKG.ERROR_RESPONSE(403, 'ERR_ADDRESS_NOT_FOUND', L_LANG);
            RETURN 403;
         ELSE
            ABSH_API_UTIL_PKG.LOG_ERROR(P_ERROR_MESSAGE => SQLERRM,
                                        P_ERROR_CODE    => SQLCODE,
                                        P_ERROR_STACK   => DBMS_UTILITY.FORMAT_ERROR_BACKTRACE,
                                        P_CALLING_PROC  => 'ABSH_API_PRIVATE_PKG.DELETE_ADDRESS',
                                        P_TABLE_NAME    => 'ABSH_CUSTOMER_ADDRESSES');
            ABSH_API_UTIL_PKG.ERROR_RESPONSE(500, 'ERR_INTERNAL', L_LANG);
            RETURN 500;
         END IF;
   END DELETE_ADDRESS;

   ------------------------------------------------------------------
   -- GET_ADDRESSES
   ------------------------------------------------------------------
   FUNCTION GET_ADDRESSES(P_PAYLOAD_JSON IN CLOB) RETURN NUMBER IS
      L_USER_ID     NUMBER;
      L_CUSTOMER_ID NUMBER;
      L_POT_CUST_ID NUMBER;
      L_DATA        CLOB;
      L_LANG        VARCHAR2(10);

      L_TOKEN     VARCHAR2(4000);
      L_CUST_ID   NUMBER; --output id pot_ud or cust_id
      L_CUST_TYPE VARCHAR2(20); --output type POTENTIAL  or CUSTOMER
   BEGIN
      ------------------------------------------------------------------
      -- Validate JSON input
      ------------------------------------------------------------------
      IF P_PAYLOAD_JSON IS NULL OR LENGTH(TRIM(P_PAYLOAD_JSON)) = 0 THEN
         ABSH_API_UTIL_PKG.ERROR_RESPONSE(400, 'ERR_MISSING_PARAM', C_DEFAULT_LANG, APEX_T_VARCHAR2('NAME', 'body'));
         RETURN 400;
      END IF;

      ------------------------------------------------------------------
      -- Parse JSON input
      ------------------------------------------------------------------
      L_TOKEN := ABSH_API_UTIL_PKG.GET_BEARER_TOKEN;
      L_LANG  := ABSH_API_UTIL_PKG.RESOLVE_LANG(JSON_VALUE(P_PAYLOAD_JSON, '$.acceptLanguage'));

      --validate api key
      ABSH_API_UTIL_PKG.VALIDATE_API_KEY(ABSH_API_UTIL_PKG.GET_APIKEY);
      ------------------------------------------------------------------
      -- Validate mandatory parameters
      ------------------------------------------------------------------
      IF L_TOKEN IS NULL OR LENGTH(TRIM(L_TOKEN)) = 0 THEN
         ABSH_API_UTIL_PKG.ERROR_RESPONSE(400, 'ERR_MISSING_PARAM', L_LANG, APEX_T_VARCHAR2('NAME', 'token'));
         RETURN 400;
      END IF;

      ------------------------------------------------------------------
      -- Authenticate user
      ------------------------------------------------------------------
      L_USER_ID := ABSH_API_PRIVATE_PKG.VALIDATE_JWT_AND_GET_USER_ID(L_TOKEN);

      ------------------------------------------------------------------
      -- Get Customer ID or Potential Customer ID
      ------------------------------------------------------------------
      ABSH_API_UTIL_PKG.GET_CUSTOMER_INFO(L_USER_ID, L_CUST_ID, L_CUST_TYPE);
      IF L_CUST_TYPE = 'CUSTOMER' THEN
         L_CUSTOMER_ID := L_CUST_ID;
      ELSIF L_CUST_TYPE = 'POTENTIAL' THEN
         L_POT_CUST_ID := L_CUST_ID;
      END IF;

      IF L_CUSTOMER_ID IS NULL AND L_POT_CUST_ID IS NULL THEN
         ABSH_API_UTIL_PKG.ERROR_RESPONSE(403, 'ERR_USER_NOT_FOUND', L_LANG);
         RETURN 403;
      END IF;

      ------------------------------------------------------------------
      -- Build response JSON
      ------------------------------------------------------------------
      SELECT NVL(JSON_ARRAYAGG(JSON_OBJECT('address_id' VALUE A.ADDRESS_ID,
                                           'address_type' VALUE A.ADDRESS_TYPE,
                                           'street' VALUE A.STREET,
                                           'address_name' VALUE A.ADDRESS_NAME,
                                           'state' VALUE A.STATE,
                                           'postal_code' VALUE A.POSTAL_CODE,
                                           'country' VALUE A.COUNTRY,
                                           'latitude' VALUE A.LATITUDE,
                                           'longitude' VALUE A.LONGITUDE,
                                           'city_id' VALUE A.CITY_ID,
                                           'is_default' VALUE A.IS_DEFAULT,
                                           'additionalPhone' VALUE A.ADDITIONAL_PHONE NULL ON NULL RETURNING CLOB)),
                 TO_CLOB('[]'))
        INTO L_DATA
        FROM ABSH_CUSTOMER_ADDRESSES A
       WHERE IS_DELETED = 0
         AND (A.CUSTOMER_ID = L_CUSTOMER_ID OR A.POT_CUSTOMER_ID = L_POT_CUST_ID);

      ------------------------------------------------------------------
      -- Success response
      ------------------------------------------------------------------
      ABSH_API_UTIL_PKG.SUCCESS_RESPONSE(P_DATA => L_DATA, P_LANG => L_LANG);
      RETURN 200;

   EXCEPTION
      WHEN OTHERS THEN
         ABSH_API_UTIL_PKG.LOG_ERROR(P_ERROR_MESSAGE => SQLERRM,
                                     P_ERROR_CODE    => SQLCODE,
                                     P_ERROR_STACK   => DBMS_UTILITY.FORMAT_ERROR_BACKTRACE,
                                     P_CALLING_PROC  => 'ABSH_API_PRIVATE_PKG.GET_ADDRESSES',
                                     P_TABLE_NAME    => 'ABSH_CUSTOMER_ADDRESSES');

         ABSH_API_UTIL_PKG.ERROR_RESPONSE(500, 'ERR_INTERNAL', L_LANG);
         RETURN 500;
   END GET_ADDRESSES;

   ------------------------------------------------------------------
   -- SET DEFAULT ADDRESS
   ------------------------------------------------------------------
   FUNCTION SET_DEFAULT_ADDRESS(P_PAYLOAD_JSON IN CLOB) RETURN NUMBER IS
      L_USER_ID     NUMBER;
      L_CUSTOMER_ID NUMBER;
      L_POT_CUST_ID NUMBER;
      L_LANG        VARCHAR2(10);
      L_TOKEN       VARCHAR2(4000);
      L_ID          NUMBER;
      L_CUST_ID     NUMBER;
      L_CUST_TYPE   VARCHAR2(20);
   BEGIN
      L_ID    := JSON_VALUE(P_PAYLOAD_JSON, '$.id' RETURNING NUMBER);
      L_LANG  := ABSH_API_UTIL_PKG.RESOLVE_LANG(JSON_VALUE(P_PAYLOAD_JSON, '$.acceptLanguage'));
      L_TOKEN := ABSH_API_UTIL_PKG.GET_BEARER_TOKEN;

      ABSH_API_UTIL_PKG.VALIDATE_API_KEY(ABSH_API_UTIL_PKG.GET_APIKEY);

      IF L_TOKEN IS NULL THEN
         ABSH_API_UTIL_PKG.ERROR_RESPONSE(400, 'ERR_MISSING_PARAM', L_LANG, APEX_T_VARCHAR2('NAME', 'token'));
         RETURN 400;
      END IF;

      IF L_ID IS NULL THEN
         ABSH_API_UTIL_PKG.ERROR_RESPONSE(400, 'ERR_MISSING_PARAM', L_LANG, APEX_T_VARCHAR2('NAME', 'id'));
         RETURN 400;
      END IF;

      L_USER_ID := ABSH_API_PRIVATE_PKG.VALIDATE_JWT_AND_GET_USER_ID(L_TOKEN);

      ABSH_API_UTIL_PKG.GET_CUSTOMER_INFO(L_USER_ID, L_CUST_ID, L_CUST_TYPE);
      IF L_CUST_TYPE = 'CUSTOMER' THEN
         L_CUSTOMER_ID := L_CUST_ID;
      ELSIF L_CUST_TYPE = 'POTENTIAL' THEN
         L_POT_CUST_ID := L_CUST_ID;
      END IF;

      IF L_CUSTOMER_ID IS NULL AND L_POT_CUST_ID IS NULL THEN
         ABSH_API_UTIL_PKG.ERROR_RESPONSE(403, 'ERR_USER_NOT_FOUND', L_LANG);
         RETURN 403;
      END IF;

      ABSH_BUSINESS_PRIVATE_PKG.SET_DEFAULT_ADDRESS(
         P_ADDRESS_ID  => L_ID,
         P_CUSTOMER_ID => L_CUSTOMER_ID,
         P_POT_CUST_ID => L_POT_CUST_ID
      );

      COMMIT;
      ABSH_API_UTIL_PKG.SUCCESS_RESPONSE(NULL);
      RETURN 200;

   EXCEPTION
      WHEN OTHERS THEN
         ROLLBACK;
         IF SQLCODE = -20002 OR SQLERRM LIKE '%ERR_ADDRESS_NOT_FOUND%' THEN
            ABSH_API_UTIL_PKG.ERROR_RESPONSE(403, 'ERR_ADDRESS_NOT_FOUND', L_LANG);
            RETURN 403;
         ELSE
            ABSH_API_UTIL_PKG.LOG_ERROR(P_ERROR_MESSAGE => SQLERRM,
                                        P_ERROR_CODE    => SQLCODE,
                                        P_ERROR_STACK   => DBMS_UTILITY.FORMAT_ERROR_BACKTRACE,
                                        P_CALLING_PROC  => 'ABSH_API_PRIVATE_PKG.SET_DEFAULT_ADDRESS',
                                        P_TABLE_NAME    => 'ABSH_CUSTOMER_ADDRESSES');
            ABSH_API_UTIL_PKG.ERROR_RESPONSE(500, 'ERR_INTERNAL', L_LANG);
            RETURN 500;
         END IF;
   END SET_DEFAULT_ADDRESS;

   -----------------------------------------------------------------------------------
   --endpoint /profile/info
   FUNCTION GET_PROFILE_INFO(P_PAYLOAD_JSON IN CLOB) RETURN NUMBER IS
      L_USER_ID     NUMBER;
      L_LANG        VARCHAR2(10);
      L_DATA        CLOB;
      L_TOKEN       VARCHAR2(4000);
      L_USER_OBJECT CLOB;
   BEGIN
      --validate api key
      ABSH_API_UTIL_PKG.VALIDATE_API_KEY(ABSH_API_UTIL_PKG.GET_APIKEY);

      IF P_PAYLOAD_JSON IS NULL OR LENGTH(TRIM(P_PAYLOAD_JSON)) = 0 THEN
         ABSH_API_UTIL_PKG.ERROR_RESPONSE(400, 'ERR_MISSING_PARAM', C_DEFAULT_LANG, APEX_T_VARCHAR2('NAME', 'body'));
         RETURN 400;
      END IF;

      L_LANG  := ABSH_API_UTIL_PKG.RESOLVE_LANG(JSON_VALUE(P_PAYLOAD_JSON, '$.acceptLanguage'));
      L_TOKEN := ABSH_API_UTIL_PKG.GET_BEARER_TOKEN;

      IF L_TOKEN IS NULL THEN
         ABSH_API_UTIL_PKG.ERROR_RESPONSE(400, 'ERR_MISSING_PARAM', L_LANG, APEX_T_VARCHAR2('NAME', 'token'));
         RETURN 400;
      END IF;

      L_USER_ID := ABSH_API_PRIVATE_PKG.VALIDATE_JWT_AND_GET_USER_ID(L_TOKEN);

      L_USER_OBJECT := ABSH_API_UTIL_PKG.GET_USER_PROFILE_OBJECT(P_USER_ID => L_USER_ID);

      SELECT JSON_OBJECT('userProfile' VALUE L_USER_OBJECT FORMAT JSON NULL ON NULL RETURNING CLOB)
        INTO L_DATA
        FROM DUAL;

      ABSH_API_UTIL_PKG.SUCCESS_RESPONSE(L_DATA);
      RETURN 200;

   EXCEPTION
      WHEN OTHERS THEN
         ABSH_API_UTIL_PKG.LOG_ERROR(SQLERRM,
                                     SQLCODE,
                                     DBMS_UTILITY.FORMAT_ERROR_BACKTRACE,
                                     'GET_PROFILE_INFO',
                                     'SM_USER');
         ABSH_API_UTIL_PKG.ERROR_RESPONSE(500, 'ERR_INTERNAL', L_LANG);
         RETURN 500;
   END GET_PROFILE_INFO;

   /* ============================================================================
   PRIVATE ENDPOINT
   NAME  : UPDATE_USER_PROFILE
   DESC  : Updates nationalId, cityId, email, name
           - Creates potential row if missing
           - Updates AR_CUSTOMER if already real customer
   ============================================================================ */

   FUNCTION UPDATE_USER_PROFILE(P_PAYLOAD_JSON IN CLOB) RETURN NUMBER IS
      L_TOKEN       VARCHAR2(4000);
      L_LANG        VARCHAR2(5);
      L_USER_ID     NUMBER;
      L_NATIONAL_ID VARCHAR2(20);
      L_CITY_ID     NUMBER;
      L_EMAIL       VARCHAR2(200);
      L_NAME        VARCHAR2(200);
      L_IMAGE_B64   CLOB;
      L_IMAGE_BLOB  BLOB;
      L_IMAGE_MIME  VARCHAR2(100);
      L_IMAGE_FILE  VARCHAR2(500);
      L_DATA        CLOB;
      L_BIRTH_DATE  DATE;
   BEGIN
      ABSH_API_UTIL_PKG.VALIDATE_API_KEY(ABSH_API_UTIL_PKG.GET_APIKEY);

      IF P_PAYLOAD_JSON IS NULL THEN
         ABSH_API_UTIL_PKG.ERROR_RESPONSE(400, 'ERR_MISSING_PARAM', C_DEFAULT_LANG, APEX_T_VARCHAR2('NAME', 'body'));
         RETURN 400;
      END IF;

      L_LANG := ABSH_API_UTIL_PKG.RESOLVE_LANG(JSON_VALUE(P_PAYLOAD_JSON, '$.acceptLanguage'));
      L_TOKEN := ABSH_API_UTIL_PKG.GET_BEARER_TOKEN;

      IF L_TOKEN IS NULL THEN
         ABSH_API_UTIL_PKG.ERROR_RESPONSE(401, 'ERR_UNAUTHORIZED', L_LANG);
         RETURN 401;
      END IF;

      L_USER_ID := ABSH_API_PRIVATE_PKG.VALIDATE_JWT_AND_GET_USER_ID(L_TOKEN);

      L_NATIONAL_ID := JSON_VALUE(P_PAYLOAD_JSON, '$.nationalId');
      L_CITY_ID     := JSON_VALUE(P_PAYLOAD_JSON, '$.cityId' RETURNING NUMBER);
      L_EMAIL       := JSON_VALUE(P_PAYLOAD_JSON, '$.email');
      L_NAME        := JSON_VALUE(P_PAYLOAD_JSON, '$.name');
      BEGIN
         L_BIRTH_DATE := TO_DATE(JSON_VALUE(P_PAYLOAD_JSON, '$.birthDate'), 'DD/MM/YYYY');
      EXCEPTION
         WHEN OTHERS THEN
            RAISE_APPLICATION_ERROR(-20001, 'ERR_INVALID_DATE_FORMAT');
      END;

      IF L_NATIONAL_ID IS NULL THEN
         ABSH_API_UTIL_PKG.ERROR_RESPONSE(400, 'ERR_MISSING_PARAM', L_LANG, APEX_T_VARCHAR2('NAME', 'nationalId'));
         RETURN 400;
      END IF;

      IF NOT REGEXP_LIKE(L_NATIONAL_ID, '^[1-4][0-9]{9}$') THEN
         ABSH_API_UTIL_PKG.ERROR_RESPONSE(400, 'ERR_INVALID_NATIONAL_ID', L_LANG);
         RETURN 400;
      END IF;

      IF L_EMAIL IS NULL THEN
         ABSH_API_UTIL_PKG.ERROR_RESPONSE(400, 'ERR_MISSING_PARAM', L_LANG, APEX_T_VARCHAR2('NAME', 'email'));
         RETURN 400;
      END IF;

      IF L_CITY_ID IS NULL THEN
         ABSH_API_UTIL_PKG.ERROR_RESPONSE(400, 'ERR_MISSING_PARAM', L_LANG, APEX_T_VARCHAR2('NAME', 'city'));
         RETURN 400;
      END IF;

      IF L_BIRTH_DATE IS NULL THEN
         ABSH_API_UTIL_PKG.ERROR_RESPONSE(400, 'ERR_MISSING_PARAM', L_LANG, APEX_T_VARCHAR2('NAME', 'birthDate'));
         RETURN 400;
      END IF;

      L_IMAGE_MIME := LOWER(JSON_VALUE(P_PAYLOAD_JSON, '$.imageMimeType'));
      L_IMAGE_FILE := JSON_VALUE(P_PAYLOAD_JSON, '$.imageFileName');

      SELECT IMAGE_BASE64
        INTO L_IMAGE_B64
        FROM JSON_TABLE(P_PAYLOAD_JSON, '$' COLUMNS(IMAGE_BASE64 CLOB PATH '$.imageBase64'));
      L_IMAGE_B64 := TRIM(BOTH '"' FROM L_IMAGE_B64);
      L_IMAGE_B64 := REGEXP_REPLACE(L_IMAGE_B64, '^data:image\/[a-zA-Z]+;base64,');

      IF L_IMAGE_B64 IS NOT NULL THEN
         IF L_IMAGE_MIME NOT LIKE 'image/%' THEN
            ABSH_API_UTIL_PKG.ERROR_RESPONSE(400, 'ERR_INVALID_IMAGE_TYPE', L_LANG);
            RETURN 400;
         END IF;
         L_IMAGE_BLOB := APEX_WEB_SERVICE.CLOBBASE642BLOB(L_IMAGE_B64);
      END IF;

      ABSH_BUSINESS_PRIVATE_PKG.UPDATE_USER_PROFILE(
         P_USER_ID     => L_USER_ID,
         P_NATIONAL_ID => L_NATIONAL_ID,
         P_CITY_ID     => L_CITY_ID,
         P_EMAIL       => L_EMAIL,
         P_NAME        => L_NAME,
         P_BIRTH_DATE  => L_BIRTH_DATE,
         P_IMAGE_BLOB  => L_IMAGE_BLOB,
         P_IMAGE_MIME  => L_IMAGE_MIME,
         P_IMAGE_FILE  => L_IMAGE_FILE
      );

      ABSH_API_UTIL_PKG.CONVERT_POTENTIAL_TO_CUSTOMER(L_USER_ID);

      SELECT ABSH_API_UTIL_PKG.GET_USER_PROFILE_OBJECT(L_USER_ID) INTO L_DATA FROM DUAL;

      COMMIT;
      ABSH_API_UTIL_PKG.SUCCESS_RESPONSE(P_STATUS_CODE => 200,
                                         P_MESSAGE_KEY => 'PROFILE_UPDATED_SUCCESS',
                                         P_LANG        => L_LANG,
                                         P_DATA        => L_DATA);
      RETURN 200;

   EXCEPTION
      WHEN OTHERS THEN
         ROLLBACK;
         ABSH_API_UTIL_PKG.LOG_ERROR(SQLERRM,
                                     SQLCODE,
                                     DBMS_UTILITY.FORMAT_ERROR_BACKTRACE,


                                     'UPDATE_USER_PROFILE',
                                     'AR_POTENTIAL_CUSTOMER');
         ABSH_API_UTIL_PKG.ERROR_RESPONSE(500, 'ERR_INTERNAL', L_LANG);
         RETURN 500;
   END UPDATE_USER_PROFILE;
   -----------------------------------------------------------------------------------
   /* ============================================================================
   PRIVATE ENDPOINT
   NAME  : SUBMIT_MEDIATION_REQUEST
   DESC  : Creates mediation RFQ using JWT user context
   NOTES :
      - No GET_IDS_FROM_USER
      - Customer resolved directly from SM_USER
      - SQL/JSON only
   ============================================================================ */

   FUNCTION SUBMIT_MEDIATION_REQUEST(P_PAYLOAD_JSON IN CLOB) RETURN NUMBER IS

      ------------------------------------------------------------------
      -- Auth & Context
      ------------------------------------------------------------------
      L_TOKEN        VARCHAR2(4000);
      L_LANG         VARCHAR2(5);
      L_USER_ID      NUMBER;
      L_CUSTOMER_ID  NUMBER;
      L_POT_CUST_ID  NUMBER;
      L_CUST_SITE_ID NUMBER;

      ------------------------------------------------------------------
      -- Input Params
      ------------------------------------------------------------------
      L_NATIONALITY_ID NUMBER;
      L_RELIGION       VARCHAR2(20);
      L_WORKED_BEFORE  VARCHAR2(5);
      L_FROM_AGE       NUMBER;
      L_TO_AGE         NUMBER;
      L_CUSTOM_SELECT  VARCHAR2(20);

      ------------------------------------------------------------------
      -- Business Vars
      ------------------------------------------------------------------
      L_MATCHED_QUOT   CLOB;
      L_QUOT_ID        NUMBER;
      L_RFQ_ID         NUMBER;
      L_DATA           CLOB;
      L_MEDIATE_AMOUNT VARCHAR2(1000);
   BEGIN

      --validate api key
      ABSH_API_UTIL_PKG.VALIDATE_API_KEY(ABSH_API_UTIL_PKG.GET_APIKEY);

      ------------------------------------------------------------------
      -- Validate Body
      ------------------------------------------------------------------
      IF P_PAYLOAD_JSON IS NULL THEN
         ABSH_API_UTIL_PKG.ERROR_RESPONSE(400, 'ERR_MISSING_PARAM', C_DEFAULT_LANG, APEX_T_VARCHAR2('NAME', 'body'));
         RETURN 400;
      END IF;

      ------------------------------------------------------------------
      -- Resolve Language
      ------------------------------------------------------------------
      L_LANG := ABSH_API_UTIL_PKG.RESOLVE_LANG(JSON_VALUE(P_PAYLOAD_JSON, '$.acceptLanguage'));

      ------------------------------------------------------------------
      -- Extract Parameters
      ------------------------------------------------------------------
      L_NATIONALITY_ID := JSON_VALUE(P_PAYLOAD_JSON, '$.nationalityId' RETURNING NUMBER);
      L_RELIGION       := JSON_VALUE(P_PAYLOAD_JSON, '$.religion');
      L_WORKED_BEFORE  := JSON_VALUE(P_PAYLOAD_JSON, '$.workedBefore');
      L_CUSTOM_SELECT  := JSON_VALUE(P_PAYLOAD_JSON, '$.customSelect');

      DECLARE
         L_AGE_RANGE VARCHAR2(20);
      BEGIN
         L_AGE_RANGE := JSON_VALUE(P_PAYLOAD_JSON, '$.age');

         IF L_AGE_RANGE IS NOT NULL THEN
            L_FROM_AGE := TO_NUMBER(SUBSTR(L_AGE_RANGE, 1, INSTR(L_AGE_RANGE, '_') - 1));
            L_TO_AGE   := TO_NUMBER(SUBSTR(L_AGE_RANGE, INSTR(L_AGE_RANGE, '_') + 1));
         END IF;
      END;

      ------------------------------------------------------------------
      -- Validate Token
      ------------------------------------------------------------------
      L_TOKEN := ABSH_API_UTIL_PKG.GET_BEARER_TOKEN;

      IF L_TOKEN IS NULL THEN
         ABSH_API_UTIL_PKG.ERROR_RESPONSE(401, 'ERR_UNAUTHORIZED', L_LANG);
         RETURN 401;
      END IF;

      L_USER_ID := ABSH_API_PRIVATE_PKG.VALIDATE_JWT_AND_GET_USER_ID(L_TOKEN);

      ------------------------------------------------------------------
      -- Resolve Customer & Potential IDs directly from SM_USER
      ------------------------------------------------------------------
      SELECT NVL(INDV_CUST_ID, CUST_ID), POT_CUST_ID
        INTO L_CUSTOMER_ID, L_POT_CUST_ID
        FROM SM_USER
       WHERE USER_ID = L_USER_ID
         AND ROLE_ID = 'INDV_CUSTOMER';

      IF L_CUSTOMER_ID IS NULL THEN
         ABSH_API_UTIL_PKG.ERROR_RESPONSE(403, 'ERR_USER_NOT_CUSTOMER', L_LANG);
         RETURN 403;
      END IF;

      ------------------------------------------------------------------
      -- Get Customer Site (first site only)
      ------------------------------------------------------------------
      BEGIN
         SELECT CUST_SITE_ID
           INTO L_CUST_SITE_ID
           FROM AR_CUSTOMER_SITE
          WHERE CUSTOMER_ID = L_CUSTOMER_ID
            AND ROWNUM = 1;
      EXCEPTION
         WHEN NO_DATA_FOUND THEN
            ABSH_API_UTIL_PKG.ERROR_RESPONSE(403, 'ERR_SITE_NOT_FOUND', L_LANG);
            RETURN 403;
      END;

      ------------------------------------------------------------------
      -- Get Matching Quotation
      ------------------------------------------------------------------
      L_MATCHED_QUOT := INDV_SAL_REQUEST_PKG.GET_MEDIATION_MATCHED_QUOT(P_NATIONALITY_ID => L_NATIONALITY_ID,
                                                                        P_WORKED_BEFORE  => L_WORKED_BEFORE,
                                                                        P_RELIGION       => L_RELIGION,
                                                                        P_FROM_AGE       => L_FROM_AGE,
                                                                        P_TO_AGE         => L_TO_AGE);

      IF L_MATCHED_QUOT IS NULL THEN
         ABSH_API_UTIL_PKG.ERROR_RESPONSE(403, 'ERR_NO_QUOTATION_FOUND', L_LANG);
         RETURN 403;
      END IF;

      L_QUOT_ID := JSON_VALUE(L_MATCHED_QUOT, '$.INDV_SAL_QUOT_ID' RETURNING NUMBER);

      L_MEDIATE_AMOUNT := SM_SETTING_PKG.FORMAT_AMOUNT(NVL(TO_NUMBER(JSON_VALUE(L_MATCHED_QUOT, '$.MEDIATE_AMOUNT')), 0));

      IF L_QUOT_ID IS NULL THEN
         ABSH_API_UTIL_PKG.ERROR_RESPONSE(403, 'ERR_NO_PACKAGE_FOUND', L_LANG);
         RETURN 403;
      END IF;
      ------------------------------------------------------------------
      -- Create Mediation Request
      ------------------------------------------------------------------
      L_RFQ_ID := INDV_SAL_REQUEST_PKG.CREATE_MEDIATION_REQUEST(P_APPLICANT_ID     => NULL,
                                                                P_CUSTOMER_ID      => L_CUSTOMER_ID,
                                                                P_CUST_SITE_ID     => L_CUST_SITE_ID,
                                                                P_INDV_SAL_QUOT_ID => L_QUOT_ID,
                                                                P_WORK_SKILL       => NULL,
                                                                P_WORKED_BEFORE    => L_WORKED_BEFORE,
                                                                P_CUST_VISA_NUMBER => NULL,
                                                                P_VISA_BLOB        => NULL,
                                                                P_VISA_LOB_DESC    => 'Customer Visa',
                                                                P_MIME_TYPE        => NULL,
                                                                P_NATIONALITY      => L_NATIONALITY_ID,
                                                                P_RELIGION         => L_RELIGION,
                                                                P_SOURCE           => 'CUSTOMER',
                                                                P_IS_CUSTOM        => CASE
                                                                                         WHEN L_CUSTOM_SELECT = 'CUSTOM' THEN
                                                                                          'YES'
                                                                                         ELSE
                                                                                          'NO'
                                                                                      END,
                                                                P_FROM_AGE         => L_FROM_AGE,
                                                                P_TO_AGE           => L_TO_AGE,
                                                                P_POTENTAIL_ID     => L_POT_CUST_ID);

      ------------------------------------------------------------------
      -- Build JSON Response
      ------------------------------------------------------------------
      SELECT JSON_OBJECT('rfqId' VALUE L_RFQ_ID, 'amount' VALUE L_MEDIATE_AMOUNT NULL ON NULL RETURNING CLOB)
        INTO L_DATA
        FROM DUAL;

      ------------------------------------------------------------------
      -- Success
      ------------------------------------------------------------------
      ABSH_API_UTIL_PKG.SUCCESS_RESPONSE(P_STATUS_CODE => 200,
                                         P_MESSAGE_KEY => 'REQUEST_CREATED',
                                         P_LANG        => L_LANG,
                                         P_DATA        => L_DATA);

      RETURN 200;

   EXCEPTION
      WHEN OTHERS THEN

         ABSH_API_UTIL_PKG.LOG_ERROR(SQLERRM,
                                     SQLCODE,
                                     DBMS_UTILITY.FORMAT_ERROR_BACKTRACE,
                                     'SUBMIT_MEDIATION_REQUEST',
                                     'INDV_SAL_REQUEST_PKG');

         ABSH_API_UTIL_PKG.ERROR_RESPONSE(500, 'ERR_INTERNAL', L_LANG);

         RETURN 500;

   END SUBMIT_MEDIATION_REQUEST;

   -----------------------------------------------------------------------------------

   --endpoint /orders/list
   -- PAGINATION ENABLED (30 ITEMS PER PAGE)
   FUNCTION GET_CUSTOMER_ORDERS(P_PAYLOAD_JSON IN CLOB) RETURN NUMBER IS
      L_TOKEN   VARCHAR2(4000);
      L_LANG    VARCHAR2(10);
      L_USER_ID NUMBER;
      L_CUSTOMER_ID NUMBER;
      L_DATA    CLOB;

      L_PAGE NUMBER := NVL(JSON_VALUE(P_PAYLOAD_JSON, '$.page' RETURNING NUMBER), 1);
      L_PAGE_SIZE CONSTANT NUMBER := 30;

      L_ORDERS_CUR SYS_REFCURSOR;

      -- Order loop variables
      L_RFQ_SYMBOL          VARCHAR2(100);
      L_INDV_RFQ_ID         NUMBER;
      L_RFQ_DATE            DATE;
      L_ORDER_DATE          VARCHAR2(50);
      L_CUSTOMER_NAME       VARCHAR2(200);
      L_RFQ_STATUS          VARCHAR2(100);
      L_RFQ_STATUS_LABEL    VARCHAR2(200);
      L_IS_CUSTOM           VARCHAR2(10);
      L_PACKAGE_NAME        VARCHAR2(200);
      L_PACKAGE_ID          NUMBER;
      L_HOURLY_ORDER_STATUS VARCHAR2(100);
      L_PACKAGE_TYPE        VARCHAR2(100);
      L_TOTAL_VISITS        NUMBER;
      L_VISITS_PER_WEEK     NUMBER;
      L_VISIT_DURATION_HRS  NUMBER;
      L_CUST_CONTRACT_ID    NUMBER;
      L_CUST_CONTRACT_SYM   VARCHAR2(100);
      L_ORDER_RATING        NUMBER;
      L_CONTRACT_EMP_ID     NUMBER;
      L_CAMP_NAME           VARCHAR2(200);
      L_CAMP_ADDRESS        VARCHAR2(1000);
      L_CAMP_LATITUDE       NUMBER;
      L_CAMP_LONGITUDE      NUMBER;
      L_CAMP_CITY           VARCHAR2(200);
      L_ADDRESS_ID          NUMBER;
   BEGIN
      L_TOKEN := ABSH_API_UTIL_PKG.GET_BEARER_TOKEN;
      L_LANG  := ABSH_API_UTIL_PKG.RESOLVE_LANG(JSON_VALUE(P_PAYLOAD_JSON, '$.acceptLanguage'));

      IF L_PAGE < 1 THEN
         L_PAGE := 1;
      END IF;

      IF L_TOKEN IS NULL THEN
         ABSH_API_UTIL_PKG.ERROR_RESPONSE(401, 'ERR_UNAUTHORIZED', L_LANG);
         RETURN 401;
      END IF;

      ABSH_API_UTIL_PKG.VALIDATE_API_KEY(ABSH_API_UTIL_PKG.GET_APIKEY);

      -- Authenticate & Get User ID
      L_USER_ID := ABSH_API_PRIVATE_PKG.VALIDATE_JWT_AND_GET_USER_ID(L_TOKEN);

      -- Resolve Customer ID
      SELECT INDV_CUST_ID
        INTO L_CUSTOMER_ID
        FROM SM_USER
       WHERE USER_ID = L_USER_ID;

      IF L_CUSTOMER_ID IS NULL THEN
         ABSH_API_UTIL_PKG.SUCCESS_RESPONSE(P_STATUS_CODE => 200, P_MESSAGE_KEY => 'ORDERS_LIST_SUCCESS', P_LANG => L_LANG, P_DATA => '[]');
         RETURN 200;
      END IF;

      -- Call Business Layer to fetch main orders list
      ABSH_BUSINESS_PRIVATE_PKG.GET_CUSTOMER_ORDERS(
          P_LANG        => L_LANG,
          P_CUSTOMER_ID => L_CUSTOMER_ID,
          P_PAGE        => L_PAGE,
          P_PAGE_SIZE   => L_PAGE_SIZE,
          P_ORDERS_CUR  => L_ORDERS_CUR
      );

      -- Serialize Cursors to JSON via Native JSON PL/SQL Object Types (No APEX_JSON)
      DECLARE
         L_OUT_ARR JSON_ARRAY_T := JSON_ARRAY_T();
         L_ITEM JSON_OBJECT_T;
         L_SCHED_ARR JSON_ARRAY_T;
         L_SCHED_OBJ JSON_OBJECT_T;
         L_WORKERS_ARR JSON_ARRAY_T;
         L_WORKER_OBJ JSON_OBJECT_T;
         L_CAMP_OBJ JSON_OBJECT_T;

         -- Schedules nested cursor variables
         L_SCHED_CUR SYS_REFCURSOR;
         L_SCHED_ID NUMBER;
         L_SCHED_DAY VARCHAR2(100);
         L_SCHED_DATE VARCHAR2(100);
         L_START_TIME VARCHAR2(10);
         L_END_TIME VARCHAR2(10);
         L_DURATION NUMBER;
         L_ACT_START VARCHAR2(10);
         L_ACT_END VARCHAR2(10);
         L_STATUS VARCHAR2(100);
         L_STATUS_LBL VARCHAR2(200);
         L_SCHED_RATABLE NUMBER;
         L_SCHED_ADDR_ID NUMBER;

         -- Workers nested cursor variables
         L_WORK_CUR SYS_REFCURSOR;
         L_W_ID NUMBER;
         L_W_NAME VARCHAR2(200);
         L_W_RATING NUMBER;
         L_W_COMM VARCHAR2(4000);
         L_W_NUM VARCHAR2(100);

         -- JSON string buffers
         L_RATING_ASPECTS CLOB;
         L_WORKERS_RATING CLOB;
         L_ADDR_JSON CLOB;
      BEGIN
         LOOP
            FETCH L_ORDERS_CUR INTO
                L_RFQ_SYMBOL, L_INDV_RFQ_ID, L_RFQ_DATE, L_ORDER_DATE, L_CUSTOMER_NAME, L_RFQ_STATUS, L_RFQ_STATUS_LABEL,
                L_IS_CUSTOM, L_PACKAGE_NAME, L_PACKAGE_ID, L_HOURLY_ORDER_STATUS, L_PACKAGE_TYPE, L_TOTAL_VISITS,
                L_VISITS_PER_WEEK, L_VISIT_DURATION_HRS, L_CUST_CONTRACT_ID, L_CUST_CONTRACT_SYM, L_ORDER_RATING,
                L_CONTRACT_EMP_ID, L_CAMP_NAME, L_CAMP_ADDRESS, L_CAMP_LATITUDE, L_CAMP_LONGITUDE, L_CAMP_CITY, L_ADDRESS_ID;
            EXIT WHEN L_ORDERS_CUR%NOTFOUND;

            L_ITEM := JSON_OBJECT_T();
            L_ITEM.PUT('orderNumber', L_RFQ_SYMBOL);
            L_ITEM.PUT('orderDate', L_ORDER_DATE);
            L_ITEM.PUT('customerName', L_CUSTOMER_NAME);
            L_ITEM.PUT('status', L_RFQ_STATUS);
            L_ITEM.PUT('isCustom', L_IS_CUSTOM);
            L_ITEM.PUT('packageName', L_PACKAGE_NAME);
            L_ITEM.PUT('hourlyOrderStatus', L_HOURLY_ORDER_STATUS);
            L_ITEM.PUT('packageType', L_PACKAGE_TYPE);
            L_ITEM.PUT('isRatable', CASE WHEN L_RFQ_STATUS = 'CONTRACTED' OR L_HOURLY_ORDER_STATUS IN ('COMPLETED', 'COMPLETED_PARTIAL_CANCEL') THEN 1 ELSE 0 END);
            L_ITEM.PUT('orderRating', L_ORDER_RATING);

            -- Rating Aspects
            IF L_PACKAGE_TYPE = 'MEDIATION' THEN
               L_ITEM.PUT_NULL('ratingAspects');
            ELSE
               L_RATING_ASPECTS := ABSH_RATING_PKG.GET_RATING_ASPECTS_BY_PACKAGE(L_PACKAGE_ID, L_LANG);
               IF L_RATING_ASPECTS IS NOT NULL THEN
                  L_ITEM.PUT('ratingAspects', JSON_ARRAY_T(L_RATING_ASPECTS));
               ELSE
                  L_ITEM.PUT_NULL('ratingAspects');
               END IF;
            END IF;

            -- Workers Rating
            IF L_PACKAGE_TYPE = 'MEDIATION' THEN
               L_ITEM.PUT_NULL('workersRating');
            ELSE
               L_WORKERS_RATING := ABSH_RATING_PKG.GET_ORDER_WORKER_RATINGS(L_RFQ_SYMBOL, P_LANG => L_LANG);
               IF L_WORKERS_RATING IS NOT NULL THEN
                  L_ITEM.PUT('workersRating', JSON_ARRAY_T(L_WORKERS_RATING));
               ELSE
                  L_ITEM.PUT_NULL('workersRating');
               END IF;
            END IF;

            -- Schedules
            L_SCHED_ARR := JSON_ARRAY_T();
            ABSH_BUSINESS_PRIVATE_PKG.GET_ORDER_SCHEDULES(L_LANG, L_INDV_RFQ_ID, L_SCHED_CUR);
            LOOP
               FETCH L_SCHED_CUR INTO
                   L_SCHED_ID, L_SCHED_DAY, L_SCHED_DATE, L_START_TIME, L_END_TIME, L_DURATION, L_ACT_START, L_ACT_END, L_STATUS, L_STATUS_LBL, L_SCHED_RATABLE, L_SCHED_ADDR_ID;
               EXIT WHEN L_SCHED_CUR%NOTFOUND;

               L_SCHED_OBJ := JSON_OBJECT_T();
               L_SCHED_OBJ.PUT('scheduleId', L_SCHED_ID);
               L_SCHED_OBJ.PUT('visitDay', L_SCHED_DAY);
               L_SCHED_OBJ.PUT('visitDate', L_SCHED_DATE);
               L_SCHED_OBJ.PUT('startTime', L_START_TIME);
               L_SCHED_OBJ.PUT('endTime', L_END_TIME);
               L_SCHED_OBJ.PUT('durationHours', L_DURATION);
               L_SCHED_OBJ.PUT('actualStartTime', L_ACT_START);
               L_SCHED_OBJ.PUT('actualEndTime', L_ACT_END);
               L_SCHED_OBJ.PUT('status', L_STATUS);
               L_SCHED_OBJ.PUT('statusLabel', L_STATUS_LBL);
               L_SCHED_OBJ.PUT('isRatable', L_SCHED_RATABLE);

               -- Nested Schedule Workers
               L_WORKERS_ARR := JSON_ARRAY_T();
               ABSH_BUSINESS_PRIVATE_PKG.GET_SCHEDULE_WORKERS(L_LANG, L_SCHED_ID, L_WORK_CUR);
               LOOP
                  FETCH L_WORK_CUR INTO L_W_ID, L_W_NAME, L_W_RATING, L_W_COMM, L_W_NUM;
                  EXIT WHEN L_WORK_CUR%NOTFOUND;

                  L_WORKER_OBJ := JSON_OBJECT_T();
                  L_WORKER_OBJ.PUT('workerId', L_W_ID);
                  L_WORKER_OBJ.PUT('workerName', L_W_NAME);
                  L_WORKER_OBJ.PUT('rating', L_W_RATING);
                  L_WORKER_OBJ.PUT('comment', L_W_COMM);
                  L_WORKER_OBJ.PUT('cv', '');
                  L_WORKERS_ARR.APPEND(L_WORKER_OBJ);
               END LOOP;
               CLOSE L_WORK_CUR;
               L_SCHED_OBJ.PUT('workers', L_WORKERS_ARR);

               L_SCHED_OBJ.PUT('addressId', L_SCHED_ADDR_ID);
               L_SCHED_ARR.APPEND(L_SCHED_OBJ);
            END LOOP;
            CLOSE L_SCHED_CUR;
            L_ITEM.PUT('schedules', L_SCHED_ARR);

            L_ITEM.PUT('totalVisits', L_TOTAL_VISITS);
            L_ITEM.PUT('visitsPerWeek', L_VISITS_PER_WEEK);
            L_ITEM.PUT('visitDurationHrs', L_VISIT_DURATION_HRS);

            -- Order Address
            IF L_ADDRESS_ID IS NOT NULL THEN
               BEGIN
                  SELECT JSON_OBJECT(
                           'addressId' VALUE ADDRESS_ID,
                           'addressType' VALUE ADDRESS_TYPE,
                           'street' VALUE STREET,
                           'addressName' VALUE ADDRESS_NAME,
                           'state' VALUE STATE,
                           'postalCode' VALUE POSTAL_CODE,
                           'country' VALUE COUNTRY,
                           'latitude' VALUE LATITUDE,
                           'longitude' VALUE LONGITUDE,
                           'cityId' VALUE CITY_ID,
                           'isDefault' VALUE IS_DEFAULT
                         )
                  INTO L_ADDR_JSON
                  FROM ABSH_CUSTOMER_ADDRESSES
                  WHERE ADDRESS_ID = L_ADDRESS_ID;
                  L_ITEM.PUT('orderAddress', JSON_OBJECT_T(L_ADDR_JSON));
               EXCEPTION
                  WHEN NO_DATA_FOUND THEN
                     L_ITEM.PUT_NULL('orderAddress');
               END;
            ELSE
               L_ITEM.PUT_NULL('orderAddress');
            END IF;

            L_ITEM.PUT('contractId', L_CUST_CONTRACT_ID);
            L_ITEM.PUT('contractNumber', L_CUST_CONTRACT_SYM);
            L_ITEM.PUT('price', 0);
            L_ITEM.PUT('originalPrice', 0);
            L_ITEM.PUT('workerCv', '');

            -- Camp Location
            IF L_CONTRACT_EMP_ID IS NOT NULL THEN
               L_CAMP_OBJ := JSON_OBJECT_T();
               L_CAMP_OBJ.PUT('name', L_CAMP_NAME);
               L_CAMP_OBJ.PUT('addressText', L_CAMP_ADDRESS);
               L_CAMP_OBJ.PUT('latitude', L_CAMP_LATITUDE);
               L_CAMP_OBJ.PUT('longitude', L_CAMP_LONGITUDE);
               L_CAMP_OBJ.PUT('city', L_CAMP_CITY);
               L_ITEM.PUT('campLocation', L_CAMP_OBJ);
            ELSE
               L_ITEM.PUT_NULL('campLocation');
            END IF;

            L_OUT_ARR.APPEND(L_ITEM);
         END LOOP;

         L_DATA := L_OUT_ARR.TO_CLOB();
      END;

      CLOSE L_ORDERS_CUR;

      ABSH_API_UTIL_PKG.SUCCESS_RESPONSE(P_STATUS_CODE => 200, P_MESSAGE_KEY => 'ORDERS_LIST_SUCCESS', P_LANG => L_LANG, P_DATA => L_DATA);
      RETURN 200;

   EXCEPTION
      WHEN OTHERS THEN
         IF L_ORDERS_CUR%ISOPEN THEN
            CLOSE L_ORDERS_CUR;
         END IF;
         ABSH_API_UTIL_PKG.LOG_ERROR(P_ERROR_MESSAGE => SQLERRM,
                                     P_ERROR_CODE    => SQLCODE,
                                     P_ERROR_STACK   => DBMS_UTILITY.FORMAT_ERROR_BACKTRACE,
                                     P_CALLING_PROC  => 'ABSH_API_PRIVATE_PKG.GET_CUSTOMER_ORDERS',
                                     P_TABLE_NAME    => 'INDV_SAL_RFQ');
         ABSH_API_UTIL_PKG.ERROR_RESPONSE(500, 'ERR_INTERNAL', L_LANG);
         RETURN 500;
   END GET_CUSTOMER_ORDERS;

   ----------------------------------------------------------------------------------------------------------------------

   /* ============================================================================
   ENDPOINT: /visit/cancel-reasons  (PUBLIC â€“ NO TOKEN REQUIRED)
   ============================================================================ */
   FUNCTION GET_CANCEL_REASONS_API(P_PAYLOAD_JSON IN CLOB) RETURN NUMBER IS
      L_LANG VARCHAR2(10);
      L_DATA CLOB;
   BEGIN
      ------------------------------------------------------------------
      -- Resolve language (optional)
      ------------------------------------------------------------------
      L_LANG := ABSH_API_UTIL_PKG.RESOLVE_LANG(JSON_VALUE(P_PAYLOAD_JSON, '$.acceptLanguage'));

      ------------------------------------------------------------------
      -- Build JSON (SQL/JSON only)
      ------------------------------------------------------------------
      SELECT NVL(JSON_ARRAYAGG(JSON_OBJECT('label' VALUE CASE
                                              WHEN L_LANG = C_DEFAULT_LANG THEN
                                               RS.REASON_LABEL_L1
                                              ELSE
                                               REASON_LABEL_L2
                                           END,
                                           'value' VALUE RS.REASON_ID NULL ON NULL RETURNING CLOB)),
                 '[]')
        INTO L_DATA
        FROM ABSH_CANCEL_REASONS RS
       WHERE RS.IS_ACTIVE = 1
         AND RS.AV_CS = 1;

      ------------------------------------------------------------------
      -- Success response
      ------------------------------------------------------------------
      ABSH_API_UTIL_PKG.SUCCESS_RESPONSE(P_STATUS_CODE => 200,
                                         P_MESSAGE_KEY => 'CANCEL_REASONS_SUCCESS',
                                         P_LANG        => L_LANG,
                                         P_DATA        => L_DATA);

      RETURN 200;

   EXCEPTION
      WHEN OTHERS THEN
         ABSH_API_UTIL_PKG.ERROR_RESPONSE(500, 'ERR_INTERNAL', L_LANG);
         RETURN 500;
   END GET_CANCEL_REASONS_API;
   /* ============================================================================
   ENDPOINT: /visit/cancel  (POST)
   ============================================================================ */
   FUNCTION CANCEL_VISIT_API(P_PAYLOAD_JSON IN CLOB) RETURN NUMBER IS
      L_TOKEN       VARCHAR2(4000);
      L_LANG        VARCHAR2(10);
      L_USER_ID     NUMBER;
      L_SCHEDULE_ID NUMBER;
      L_REASON_ID   NUMBER;
      L_REASON_NOTE VARCHAR2(500);
   BEGIN
      ------------------------------------------------------------------
      -- Parse
      ------------------------------------------------------------------
      L_TOKEN       := ABSH_API_UTIL_PKG.GET_BEARER_TOKEN;
      L_LANG        := ABSH_API_UTIL_PKG.RESOLVE_LANG(JSON_VALUE(P_PAYLOAD_JSON, '$.acceptLanguage'));
      L_SCHEDULE_ID := JSON_VALUE(P_PAYLOAD_JSON, '$.scheduleId' RETURNING NUMBER);
      L_REASON_ID   := JSON_VALUE(P_PAYLOAD_JSON, '$.reasonId' RETURNING NUMBER);
      L_REASON_NOTE := JSON_VALUE(P_PAYLOAD_JSON, '$.reasonNote');

      ------------------------------------------------------------------
      -- Auth
      ------------------------------------------------------------------
      IF L_TOKEN IS NULL THEN
         ABSH_API_UTIL_PKG.ERROR_RESPONSE(401, 'ERR_UNAUTHORIZED', L_LANG);
         RETURN 401;
      END IF;

      IF L_SCHEDULE_ID IS NULL THEN
         ABSH_API_UTIL_PKG.ERROR_RESPONSE(400, 'ERR_MISSING_PARAM', L_LANG, APEX_T_VARCHAR2('NAME', 'scheduleId'));
         RETURN 400;
      END IF;

      IF L_REASON_ID IS NULL THEN
         ABSH_API_UTIL_PKG.ERROR_RESPONSE(400, 'ERR_MISSING_PARAM', L_LANG, APEX_T_VARCHAR2('NAME', 'reasonId'));
         RETURN 400;
      END IF;

      ABSH_API_UTIL_PKG.VALIDATE_API_KEY(ABSH_API_UTIL_PKG.GET_APIKEY);

      L_USER_ID := ABSH_API_PRIVATE_PKG.VALIDATE_JWT_AND_GET_USER_ID(L_TOKEN);
      -- CHECK VISIT BELONGS TO USER_ID
      ------------------------------------------------------------------
      -- Validate visit belongs to logged-in user
      ------------------------------------------------------------------
      DECLARE
         L_DUMMY NUMBER;
      BEGIN
         SELECT 1
           INTO L_DUMMY
           FROM ABSH_VISIT_SCHEDULE VS
           JOIN INDV_SAL_RFQ ISR ON ISR.INDV_RFQ_ID = VS.INDV_RFQ_ID
           JOIN SM_USER U ON U.USER_ID = L_USER_ID
                         AND ISR.CUSTOMER_ID = U.INDV_CUST_ID
          WHERE VS.SCHEDULE_ID = L_SCHEDULE_ID;

      EXCEPTION
         WHEN NO_DATA_FOUND THEN
            ABSH_API_UTIL_PKG.ERROR_RESPONSE(P_STATUS_CODE => 403,
                                             P_MESSAGE_KEY => 'ERR_VISIT_NOT_OWNED',
                                             P_LANG        => L_LANG);
            RETURN 403;
      END;
      ------------------------------------------------------------------
      -- Business call
      ------------------------------------------------------------------

      ABSH_VISIT_PKG.CANCEL_VISIT(P_SCHEDULE_ID => L_SCHEDULE_ID,
                                              P_REASON_ID   => L_REASON_ID,
                                              P_REASON_NOTE => L_REASON_NOTE);

      ------------------------------------------------------------------
      -- Success
      ------------------------------------------------------------------
      ABSH_API_UTIL_PKG.SUCCESS_RESPONSE(P_STATUS_CODE => 200,
                                         P_MESSAGE_KEY => 'VISIT_CANCEL_SUCCESS',
                                         P_LANG        => L_LANG,
                                         P_DATA        => NULL);

      RETURN 200;

   EXCEPTION
      WHEN OTHERS THEN
         ABSH_API_UTIL_PKG.ERROR_RESPONSE(500, 'ERR_INTERNAL', L_LANG);
         RETURN 500;
   END CANCEL_VISIT_API;
   --------------------------------------------------------------------------------

   /* ============================================================================
   ENDPOINT: /visit/reschedule-dates  (POST)
   ============================================================================ */
   FUNCTION GET_RESCHEDULE_DATES_API(P_PAYLOAD_JSON IN CLOB) RETURN NUMBER IS
      L_TOKEN       VARCHAR2(4000);
      L_LANG        VARCHAR2(10);
      L_USER_ID     NUMBER;
      L_SCHEDULE_ID NUMBER;
      L_FROM_DATE   DATE;
      L_MAX_DATES   NUMBER := 10;
      L_DATA        CLOB;
   BEGIN
      ------------------------------------------------------------------
      -- Parse
      ------------------------------------------------------------------
      L_TOKEN       := ABSH_API_UTIL_PKG.GET_BEARER_TOKEN;
      L_LANG        := ABSH_API_UTIL_PKG.RESOLVE_LANG(JSON_VALUE(P_PAYLOAD_JSON, '$.acceptLanguage'));
      L_SCHEDULE_ID := JSON_VALUE(P_PAYLOAD_JSON, '$.scheduleId' RETURNING NUMBER);
      L_FROM_DATE   := SYSDATE;

      ------------------------------------------------------------------
      -- Auth
      ------------------------------------------------------------------
      IF L_TOKEN IS NULL THEN
         ABSH_API_UTIL_PKG.ERROR_RESPONSE(401, 'ERR_UNAUTHORIZED', L_LANG);
         RETURN 401;
      END IF;

      IF L_SCHEDULE_ID IS NULL THEN
         ABSH_API_UTIL_PKG.ERROR_RESPONSE(400, 'ERR_MISSING_PARAM', L_LANG, APEX_T_VARCHAR2('NAME', 'scheduleId'));
         RETURN 400;
      END IF;

      ABSH_API_UTIL_PKG.VALIDATE_API_KEY(ABSH_API_UTIL_PKG.GET_APIKEY);

      L_USER_ID := ABSH_API_PRIVATE_PKG.VALIDATE_JWT_AND_GET_USER_ID(L_TOKEN);

      -- CHECK VISIT BELONGS TO USER_ID
      ------------------------------------------------------------------
      -- Validate visit belongs to logged-in user
      ------------------------------------------------------------------
      DECLARE
         L_DUMMY NUMBER;
      BEGIN
         SELECT 1
           INTO L_DUMMY
           FROM ABSH_VISIT_SCHEDULE VS
           JOIN INDV_SAL_RFQ ISR ON ISR.INDV_RFQ_ID = VS.INDV_RFQ_ID
           JOIN SM_USER U ON U.USER_ID = L_USER_ID
                         AND ISR.CUSTOMER_ID = U.INDV_CUST_ID
          WHERE VS.SCHEDULE_ID = L_SCHEDULE_ID;

      EXCEPTION
         WHEN NO_DATA_FOUND THEN
            ABSH_API_UTIL_PKG.ERROR_RESPONSE(P_STATUS_CODE => 403,
                                             P_MESSAGE_KEY => 'ERR_VISIT_NOT_OWNED',
                                             P_LANG        => L_LANG);
            RETURN 403;
      END;
      ------------------------------------------------------------------
      -- Build JSON from table function
      ------------------------------------------------------------------


      SELECT NVL(JSON_ARRAYAGG(TO_CHAR(COLUMN_VALUE, 'DD/MM/YYYY') RETURNING CLOB), '[]')
        INTO L_DATA
        FROM TABLE(ABSH_VISIT_PKG.GET_NEXT_RESCHEDULE_DATES(P_SCHEDULE_ID => L_SCHEDULE_ID,
                                                                        P_FROM_DATE   => L_FROM_DATE,
                                                                        P_MAX_DATES   => L_MAX_DATES));

      ------------------------------------------------------------------
      -- Success
      ------------------------------------------------------------------
      ABSH_API_UTIL_PKG.SUCCESS_RESPONSE(P_STATUS_CODE => 200,
                                         P_MESSAGE_KEY => 'RESCHEDULE_DATES_SUCCESS',
                                         P_LANG        => L_LANG,
                                         P_DATA        => L_DATA);

      RETURN 200;

   EXCEPTION
      WHEN OTHERS THEN
         ABSH_API_UTIL_PKG.ERROR_RESPONSE(500, 'ERR_INTERNAL', L_LANG);
         RETURN 500;
   END GET_RESCHEDULE_DATES_API;
   --------------------------------------------------------------------------------

   /* ============================================================================
   ENDPOINT: /visit/reschedule  (POST)
   ============================================================================ */
   FUNCTION RESCHEDULE_VISIT_API(P_PAYLOAD_JSON IN CLOB) RETURN NUMBER IS
      L_TOKEN           VARCHAR2(4000);
      L_LANG            VARCHAR2(10);
      L_USER_ID         NUMBER;
      L_SCHEDULE_ID     NUMBER;
      L_NEW_DATE        DATE;
      L_NEW_SCHEDULE_ID NUMBER;
      L_DATA            CLOB;
      L_REASON_ID       NUMBER;
      L_REASON_NOTE     VARCHAR2(500);
   BEGIN
      ------------------------------------------------------------------
      -- Parse
      ------------------------------------------------------------------
      L_TOKEN       := ABSH_API_UTIL_PKG.GET_BEARER_TOKEN;
      L_LANG        := ABSH_API_UTIL_PKG.RESOLVE_LANG(JSON_VALUE(P_PAYLOAD_JSON, '$.acceptLanguage'));
      L_SCHEDULE_ID := JSON_VALUE(P_PAYLOAD_JSON, '$.scheduleId' RETURNING NUMBER);
      L_NEW_DATE    := TO_DATE(JSON_VALUE(P_PAYLOAD_JSON, '$.newVisitDate'), 'YYYY-MM-DD');
      L_REASON_ID   := JSON_VALUE(P_PAYLOAD_JSON, '$.reasonId' RETURNING NUMBER);
      L_REASON_NOTE := JSON_VALUE(P_PAYLOAD_JSON, '$.reasonNote');

      ------------------------------------------------------------------
      -- Auth
      ------------------------------------------------------------------
      IF L_TOKEN IS NULL THEN
         ABSH_API_UTIL_PKG.ERROR_RESPONSE(401, 'ERR_UNAUTHORIZED', L_LANG);
         RETURN 401;
      END IF;

      IF L_SCHEDULE_ID IS NULL THEN
         ABSH_API_UTIL_PKG.ERROR_RESPONSE(400, 'ERR_MISSING_PARAM', L_LANG, APEX_T_VARCHAR2('NAME', 'scheduleId'));
         RETURN 400;
      END IF;

      IF L_NEW_DATE IS NULL THEN
         ABSH_API_UTIL_PKG.ERROR_RESPONSE(400, 'ERR_MISSING_PARAM', L_LANG, APEX_T_VARCHAR2('NAME', 'newVisitDate'));
         RETURN 400;
      END IF;

      IF L_REASON_ID IS NULL THEN
         ABSH_API_UTIL_PKG.ERROR_RESPONSE(400, 'ERR_MISSING_PARAM', L_LANG, APEX_T_VARCHAR2('NAME', 'reasonId'));
         RETURN 400;
      END IF;

      ABSH_API_UTIL_PKG.VALIDATE_API_KEY(ABSH_API_UTIL_PKG.GET_APIKEY);

      L_USER_ID := ABSH_API_PRIVATE_PKG.VALIDATE_JWT_AND_GET_USER_ID(L_TOKEN);

      -- CHECK VISIT BELONGS TO USER_ID
      ------------------------------------------------------------------
      -- Validate visit belongs to logged-in user
      ------------------------------------------------------------------
      DECLARE
         L_DUMMY NUMBER;
      BEGIN
         SELECT 1
           INTO L_DUMMY
           FROM ABSH_VISIT_SCHEDULE VS
           JOIN INDV_SAL_RFQ ISR ON ISR.INDV_RFQ_ID = VS.INDV_RFQ_ID
           JOIN SM_USER U ON U.USER_ID = L_USER_ID
                         AND ISR.CUSTOMER_ID = U.INDV_CUST_ID
          WHERE VS.SCHEDULE_ID = L_SCHEDULE_ID;

      EXCEPTION
         WHEN NO_DATA_FOUND THEN
            ABSH_API_UTIL_PKG.ERROR_RESPONSE(P_STATUS_CODE => 403,
                                             P_MESSAGE_KEY => 'ERR_VISIT_NOT_OWNED',
                                             P_LANG        => L_LANG);
            RETURN 403;
      END;

      ------------------------------------------------------------------
      -- Business call
      ------------------------------------------------------------------
      L_NEW_SCHEDULE_ID := ABSH_VISIT_PKG.CANCEL_AND_RESCHEDULE_VISIT(P_SCHEDULE_ID    => L_SCHEDULE_ID,
                                                                                  P_NEW_VISIT_DATE => L_NEW_DATE,
                                                                                  P_REASON_ID      => L_REASON_ID,
                                                                                  P_REASON_NOTE    => L_REASON_NOTE);

      ------------------------------------------------------------------
      -- Build response JSON
      ------------------------------------------------------------------
      SELECT JSON_OBJECT('newScheduleId' VALUE L_NEW_SCHEDULE_ID NULL ON NULL RETURNING CLOB) INTO L_DATA FROM DUAL;

      ------------------------------------------------------------------
      -- Success
      ------------------------------------------------------------------
      ABSH_API_UTIL_PKG.SUCCESS_RESPONSE(P_STATUS_CODE => 200,
                                         P_MESSAGE_KEY => 'VISIT_RESCHEDULE_SUCCESS',
                                         P_LANG        => L_LANG,
                                         P_DATA        => L_DATA);

      RETURN 200;

   EXCEPTION
      WHEN OTHERS THEN
         ABSH_API_UTIL_PKG.ERROR_RESPONSE(500, 'ERR_INTERNAL', L_LANG);
         RETURN 500;
   END RESCHEDULE_VISIT_API;
   -----------------------------------------------------------------------------------

   FUNCTION DEACTIVATE_ACCOUNT(P_PAYLOAD_JSON IN CLOB) RETURN NUMBER IS
      L_TOKEN          VARCHAR2(4000);
      L_LANG           VARCHAR2(10);
      L_USER_ID        NUMBER;
      L_DATA           CLOB;
      L_REACTIVATE_JWT VARCHAR2(4000);
      L_BASE_URL       VARCHAR2(1000);
      L_REACT_URL      VARCHAR2(2000);
   BEGIN
      L_TOKEN := ABSH_API_UTIL_PKG.GET_BEARER_TOKEN;
      L_LANG  := NVL(ABSH_API_UTIL_PKG.RESOLVE_LANG(JSON_VALUE(P_PAYLOAD_JSON, '$.acceptLanguage')), C_DEFAULT_LANG);

      ABSH_API_UTIL_PKG.VALIDATE_API_KEY(ABSH_API_UTIL_PKG.GET_APIKEY);

      IF L_TOKEN IS NULL THEN
         ABSH_API_UTIL_PKG.ERROR_RESPONSE(400, 'ERR_MISSING_PARAM', L_LANG, APEX_T_VARCHAR2('NAME', 'token'));
         RETURN 400;
      END IF;

      L_USER_ID := VALIDATE_JWT_AND_GET_USER_ID(L_TOKEN);

      ABSH_BUSINESS_PRIVATE_PKG.DEACTIVATE_ACCOUNT(L_USER_ID);

      L_REACTIVATE_JWT := GENERATE_JWT(L_USER_ID);
      L_BASE_URL       := OWA_UTIL.GET_CGI_ENV('REQUEST_PROTOCOL') || '://' || OWA_UTIL.GET_CGI_ENV('HTTP_HOST');
      L_REACT_URL      := L_BASE_URL || '/ords/RUNERP/absh-private/profile/reactivate?token=' || L_REACTIVATE_JWT;

      SELECT JSON_OBJECT('reactivationUrl' VALUE L_REACT_URL NULL ON NULL RETURNING CLOB) INTO L_DATA FROM DUAL;

      COMMIT;
      ABSH_API_UTIL_PKG.SUCCESS_RESPONSE(P_DATA        => L_DATA,
                                         P_STATUS_CODE => 200,
                                         P_MESSAGE_KEY => 'ACCOUNT_DEACTIVATED',
                                         P_LANG        => L_LANG);
      RETURN 200;

   EXCEPTION
      WHEN OTHERS THEN
         ROLLBACK;
         IF SQLCODE = -20003 OR SQLERRM LIKE '%ERR_ACCOUNT_ALREADY_DEACTIVATED%' THEN
            ABSH_API_UTIL_PKG.ERROR_RESPONSE(409, 'ERR_ACCOUNT_ALREADY_DEACTIVATED', L_LANG);
            RETURN 409;
         ELSE
            ABSH_API_UTIL_PKG.LOG_ERROR(P_ERROR_MESSAGE => SQLERRM,
                                        P_ERROR_CODE    => SQLCODE,
                                        P_ERROR_STACK   => DBMS_UTILITY.FORMAT_ERROR_BACKTRACE,
                                        P_CALLING_PROC  => 'DEACTIVATE_ACCOUNT',
                                        P_TABLE_NAME    => 'SM_USER');
            ABSH_API_UTIL_PKG.ERROR_RESPONSE(500, 'ERR_INTERNAL', L_LANG);
            RETURN 500;
         END IF;
   END DEACTIVATE_ACCOUNT;

   -----------------------------------------------------------------------------------
   FUNCTION REACTIVATE_ACCOUNT RETURN NUMBER IS
      L_TOKEN      VARCHAR2(4000);
      L_USER_ID    NUMBER;
   BEGIN
      L_TOKEN := OWA_UTIL.GET_CGI_ENV('QUERY_STRING');

      IF L_TOKEN IS NULL THEN
         HTP.P('Invalid link.');
         RETURN 400;
      END IF;

      L_TOKEN := REGEXP_REPLACE(L_TOKEN, '^token=');

      L_USER_ID := VALIDATE_JWT_AND_GET_USER_ID(L_TOKEN, P_ALLOW_DEACTIVATED => TRUE);

      ABSH_BUSINESS_PRIVATE_PKG.REACTIVATE_ACCOUNT(L_USER_ID);

      COMMIT;

      OWA_UTIL.MIME_HEADER('text/html', FALSE);
      HTP.P('Cache-Control: no-cache');
      OWA_UTIL.HTTP_HEADER_CLOSE;

      HTP.P('
   <html>
   <head>
      <meta charset="UTF-8">
      <title>Account Reactivated</title>
      <style>
         body { font-family: Arial; text-align:center; padding:40px; }
         .box { max-width:600px; margin:auto; }
         h1 { color:green; }
         .ar { direction:rtl; margin-top:40px; }
      </style>
   </head>
   <body>
      <div class="box">
         <h1>✅ Your account has been reactivated</h1>
         <p>Please open the mobile application and login again.</p>

         <div class="ar">
            <h1>✅ تم إعادة تفعيل حسابك بنجاح</h1>
            <p>يرجى فتح التطبيق وتسجيل الدخول مرة أخرى.</p>
         </div>
      </div>
   </body>
   </html>');

      RETURN 200;

   EXCEPTION
      WHEN OTHERS THEN
         ROLLBACK;
         IF SQLCODE = -20004 OR SQLERRM LIKE '%ERR_REACTIVATION_EXPIRED%' THEN
            HTP.P('Reactivation window expired.');
            RETURN 403;
         ELSE
            ABSH_API_UTIL_PKG.LOG_ERROR(P_ERROR_MESSAGE => SQLERRM,
                                        P_ERROR_CODE    => SQLCODE,
                                        P_ERROR_STACK   => DBMS_UTILITY.FORMAT_ERROR_BACKTRACE,
                                        P_CALLING_PROC  => 'REACTIVATE_ACCOUNT',
                                        P_TABLE_NAME    => 'SM_USER');
            HTP.P('Unexpected error occurred.');
            RETURN 500;
         END IF;
   END REACTIVATE_ACCOUNT;
   -----------------------------------------------------------------------------------
   --dev only --TODO REMOVE
   FUNCTION GET_USER_ID RETURN NUMBER IS
      L_TOKEN   VARCHAR2(4000);
      L_USER_ID NUMBER;
      L_DATA    CLOB;
   BEGIN
      L_TOKEN := ABSH_API_UTIL_PKG.GET_BEARER_TOKEN;

      IF L_TOKEN IS NULL THEN
         HTP.P('Invalid link.');
         RETURN 400;
      END IF;

      ------------------------------------------------------------------
      -- Validate JWT
      ------------------------------------------------------------------
      L_USER_ID := VALIDATE_JWT_AND_GET_USER_ID(L_TOKEN, P_ALLOW_DEACTIVATED => TRUE);
      SELECT JSON_OBJECT('userId' VALUE L_USER_ID NULL ON NULL RETURNING CLOB) INTO L_DATA FROM DUAL;

      ABSH_API_UTIL_PKG.SUCCESS_RESPONSE(P_DATA => L_DATA, P_STATUS_CODE => 200, P_MESSAGE_KEY => 'OK');
      RETURN 200;
   END GET_USER_ID;
   -----------------------------------------------------------------------------------
   FUNCTION REGISTER_DEVICE_TOKEN(P_PAYLOAD_JSON IN CLOB) RETURN NUMBER IS

      L_TOKEN VARCHAR2(4000);
      L_LANG  VARCHAR2(10);

      L_FCM_TOKEN   VARCHAR2(4000);
      L_DEVICE_TYPE VARCHAR2(20);

      L_USER_ID NUMBER;
      L_DATA    CLOB;

   BEGIN

      ---------------------------------------------------------
      -- Parse JSON
      ---------------------------------------------------------
      L_TOKEN := ABSH_API_UTIL_PKG.GET_BEARER_TOKEN;
      L_LANG  := ABSH_API_UTIL_PKG.RESOLVE_LANG(JSON_VALUE(P_PAYLOAD_JSON, '$.acceptLanguage'));

      L_FCM_TOKEN   := JSON_VALUE(P_PAYLOAD_JSON, '$.fcmToken');
      L_DEVICE_TYPE := UPPER(JSON_VALUE(P_PAYLOAD_JSON, '$.deviceType'));

      ---------------------------------------------------------
      -- Validate API key
      ---------------------------------------------------------
      ABSH_API_UTIL_PKG.VALIDATE_API_KEY(ABSH_API_UTIL_PKG.GET_APIKEY);

      ---------------------------------------------------------
      -- Mandatory validation
      ---------------------------------------------------------
      IF L_TOKEN IS NULL THEN
         ABSH_API_UTIL_PKG.ERROR_RESPONSE(P_STATUS_CODE => 400,
                                          P_MESSAGE_KEY => 'ERR_MISSING_PARAM',
                                          P_LANG        => L_LANG,
                                          P_PARAMS      => APEX_T_VARCHAR2('NAME', 'token'));
         RETURN 400;
      END IF;

      IF L_FCM_TOKEN IS NULL THEN
         ABSH_API_UTIL_PKG.ERROR_RESPONSE(P_STATUS_CODE => 400,
                                          P_MESSAGE_KEY => 'ERR_MISSING_PARAM',
                                          P_LANG        => L_LANG,
                                          P_PARAMS      => APEX_T_VARCHAR2('NAME', 'fcmToken'));
         RETURN 400;
      END IF;

      IF L_DEVICE_TYPE IS NULL THEN
         ABSH_API_UTIL_PKG.ERROR_RESPONSE(P_STATUS_CODE => 400,
                                          P_MESSAGE_KEY => 'ERR_MISSING_PARAM',
                                          P_LANG        => L_LANG,
                                          P_PARAMS      => APEX_T_VARCHAR2('NAME', 'deviceType'));
         RETURN 400;
      END IF;

      ---------------------------------------------------------
      -- Resolve user
      ---------------------------------------------------------
      L_USER_ID := ABSH_API_PRIVATE_PKG.VALIDATE_JWT_AND_GET_USER_ID(L_TOKEN);

      ---------------------------------------------------------
      -- Register token
      ---------------------------------------------------------
      ABSH_FCM_PKG.REGISTER_TOKEN(P_USER_ID     => L_USER_ID,
                                              P_FCM_TOKEN   => L_FCM_TOKEN,
                                              P_DEVICE_TYPE => L_DEVICE_TYPE);


      ---------------------------------------------------------
      -- Build response
      ---------------------------------------------------------
      SELECT JSON_OBJECT('registered' VALUE 1 NULL ON NULL RETURNING CLOB) INTO L_DATA FROM DUAL;

      ABSH_API_UTIL_PKG.SUCCESS_RESPONSE(P_STATUS_CODE => 200,
                                         P_MESSAGE_KEY => 'DEVICE_REGISTERED',
                                         P_LANG        => L_LANG,
                                         P_DATA        => L_DATA);

      RETURN 200;

   EXCEPTION
      WHEN OTHERS THEN

         ABSH_API_UTIL_PKG.LOG_ERROR(P_ERROR_MESSAGE => SQLERRM,
                                     P_ERROR_CODE    => SQLCODE,
                                     P_ERROR_STACK   => DBMS_UTILITY.FORMAT_ERROR_BACKTRACE,
                                     P_CALLING_PROC  => 'ABSH_API_PRIVATE_PKG.REGISTER_DEVICE_TOKEN',
                                     P_TABLE_NAME    => 'ABSH_USER_FCM_TOKENS');

         ABSH_API_UTIL_PKG.ERROR_RESPONSE(P_STATUS_CODE => 500, P_MESSAGE_KEY => 'ERR_INTERNAL', P_LANG => L_LANG);

         RETURN 500;

   END REGISTER_DEVICE_TOKEN;

   -----------------------------------------------------------------------------------
   FUNCTION UPLOAD_PROFILE_IMAGE(P_BLOB IN BLOB) RETURN NUMBER IS
      L_TOKEN   VARCHAR2(4000);
      L_USER_ID NUMBER;
      L_LOB_ID  NUMBER;
      L_FILE    VARCHAR2(200);
      L_DATA    CLOB;
   BEGIN
      ABSH_API_UTIL_PKG.VALIDATE_API_KEY(P_API_KEY => ABSH_API_UTIL_PKG.GET_APIKEY);

      L_TOKEN := ABSH_API_UTIL_PKG.GET_BEARER_TOKEN;

      IF L_TOKEN IS NULL THEN
         ABSH_API_UTIL_PKG.ERROR_RESPONSE(P_STATUS_CODE => 400,
                                          P_MESSAGE_KEY => 'ERR_MISSING_PARAM',
                                          P_PARAMS      => APEX_T_VARCHAR2('NAME', 'token'));
         RETURN 400;
      END IF;

      IF P_BLOB IS NULL THEN
         ABSH_API_UTIL_PKG.ERROR_RESPONSE(P_STATUS_CODE => 400,
                                          P_MESSAGE_KEY => 'ERR_MISSING_PARAM',
                                          P_PARAMS      => APEX_T_VARCHAR2('NAME', 'image'));
         RETURN 400;
      END IF;

      L_USER_ID := ABSH_API_PRIVATE_PKG.VALIDATE_JWT_AND_GET_USER_ID(P_JWT => L_TOKEN);

      ABSH_BUSINESS_PRIVATE_PKG.UPLOAD_PROFILE_IMAGE(
         P_USER_ID => L_USER_ID,
         P_BLOB    => P_BLOB,
         P_FILE    => L_FILE,
         P_LOB_ID  => L_LOB_ID
      );

      SELECT JSON_OBJECT('lobId' VALUE L_LOB_ID, 'fileName' VALUE L_FILE NULL ON NULL RETURNING CLOB)
        INTO L_DATA
        FROM DUAL;

      COMMIT;
      ABSH_API_UTIL_PKG.SUCCESS_RESPONSE(P_STATUS_CODE => 200, P_DATA => L_DATA);
      RETURN 200;

   EXCEPTION
      WHEN OTHERS THEN
         ROLLBACK;
         ABSH_API_UTIL_PKG.LOG_ERROR(P_ERROR_MESSAGE => SQLERRM,
                                     P_ERROR_CODE    => SQLCODE,
                                     P_ERROR_STACK   => DBMS_UTILITY.FORMAT_ERROR_BACKTRACE,
                                     P_CALLING_PROC  => 'ABSH_API_PRIVATE_PKG.UPLOAD_PROFILE_IMAGE',
                                     P_TABLE_NAME    => 'RUNERP_LOB.SM_LOB');

         ABSH_API_UTIL_PKG.ERROR_RESPONSE(P_STATUS_CODE => 500, P_MESSAGE_KEY => 'ERR_INTERNAL');
         RETURN 500;
   END UPLOAD_PROFILE_IMAGE;
   -----------------------------------------------------------------------------------
   FUNCTION CREATE_ORDER_HOURLY(P_PAYLOAD_JSON IN CLOB) RETURN NUMBER IS
      ------------------------------------------------------------------
      -- Variables
      ------------------------------------------------------------------
      L_LANG             VARCHAR2(10);
      L_CUST_SITE_ID     VARCHAR2(100);
      L_CUSTOMER_ID      NUMBER;
      L_POT_CUST_ID      NUMBER;
      L_CUST_ID          NUMBER;
      L_CUST_TYPE        VARCHAR2(200);
      L_PACKAGE_ID       NUMBER;
      L_COMBINATION_CODE VARCHAR2(500);
      L_PROMOCODE        VARCHAR2(100);
      L_TOTAL_PRICE      NUMBER;
      L_QUOT_PRICE       NUMBER;
      L_VISIT_DATA_JSON  CLOB;
      L_ORDER_ADDRESS_ID NUMBER;
      L_WITH_OUT_DET     VARCHAR2(1);
      L_TOKEN            VARCHAR2(1000);
      L_USER_ID          NUMBER;
      V_RFQ_ID           NUMBER;
      V_CONTRACT_SYMBOL  VARCHAR2(3000);
      V_STATUS           VARCHAR2(500);
      V_MESSAGE          CLOB;
      V_STEP             VARCHAR2(200);
      L_DATA             CLOB;
      L_START_TIME       VARCHAR2(100);
      L_END_TIME         VARCHAR2(100);
      L_ALLOWED_DAYS     CLOB;
      L_VALID_DATE_FROM  DATE;
      L_VALID_DATE_TO    DATE;
      L_RFQ_SYMBOL       VARCHAR2(99);

   BEGIN
      ------------------------------------------------------------------
      -- Parse JSON input
      ------------------------------------------------------------------
      L_LANG             := NVL(JSON_VALUE(P_PAYLOAD_JSON, '$.acceptLanguage'), C_DEFAULT_LANG);
      L_PACKAGE_ID       := JSON_VALUE(P_PAYLOAD_JSON, '$.packageId');
      L_COMBINATION_CODE := JSON_VALUE(P_PAYLOAD_JSON, '$.combinationCode');
      L_VISIT_DATA_JSON  := JSON_QUERY(P_PAYLOAD_JSON, '$.visitDataJson');
      L_ORDER_ADDRESS_ID := JSON_VALUE(P_PAYLOAD_JSON, '$.orderAddressId');
      L_PROMOCODE        := JSON_VALUE(P_PAYLOAD_JSON, '$.promoCode'); -- Ignore
      L_WITH_OUT_DET     := 'N';
      L_TOKEN            := ABSH_API_UTIL_PKG.GET_BEARER_TOKEN;
      ------------------------------------------------------------------
      -- Validate token
      ------------------------------------------------------------------
      IF L_TOKEN IS NULL THEN
         ABSH_API_UTIL_PKG.ERROR_RESPONSE(400, 'ERR_MISSING_PARAM', L_LANG, APEX_T_VARCHAR2('NAME', 'token'));
         RETURN 400;
      END IF;

      ------------------------------------------------------------------
      -- Validate mandatory parameters
      ------------------------------------------------------------------
      IF L_PACKAGE_ID IS NULL THEN
         ABSH_API_UTIL_PKG.ERROR_RESPONSE(400, 'ERR_MISSING_PARAM', L_LANG, APEX_T_VARCHAR2('NAME', 'packageId'));
         RETURN 400;
      END IF;

      IF L_ORDER_ADDRESS_ID IS NULL THEN
         ABSH_API_UTIL_PKG.ERROR_RESPONSE(400, 'ERR_MISSING_PARAM', L_LANG, APEX_T_VARCHAR2('NAME', 'orderAddressId'));
         RETURN 400;
      END IF;

      ABSH_API_UTIL_PKG.VALIDATE_API_KEY(ABSH_API_UTIL_PKG.GET_APIKEY);

      ------------------------------------------------------------------
      -- Validate JWT and get user ID
      ------------------------------------------------------------------
      L_USER_ID := ABSH_API_PRIVATE_PKG.VALIDATE_JWT_AND_GET_USER_ID(L_TOKEN);
      ABSH_API_UTIL_PKG.VALIDATE_USER_EXISTS(L_USER_ID);

      ------------------------------------------------------------------
      -- Get Customer Info from JWT
      ------------------------------------------------------------------
      ABSH_API_UTIL_PKG.GET_CUSTOMER_INFO(L_USER_ID, L_CUST_ID, L_CUST_TYPE);

      IF L_CUST_TYPE = 'CUSTOMER' THEN
         L_CUSTOMER_ID := L_CUST_ID;
      ELSIF L_CUST_TYPE = 'POTENTIAL' THEN
         L_POT_CUST_ID := L_CUST_ID;
      END IF;

      IF L_CUSTOMER_ID IS NULL AND L_POT_CUST_ID IS NULL THEN
         ABSH_API_UTIL_PKG.ERROR_RESPONSE(403, 'ERR_USER_NOT_FOUND', L_LANG);
         RETURN 403;
      END IF;

      ------------------------------------------------------------------
      -- Check and validate customer profile
      ------------------------------------------------------------------
      IF ABSH_API_UTIL_PKG.IS_PROFILE_COMPLETE(L_USER_ID) = 0 THEN
         ABSH_API_UTIL_PKG.ERROR_RESPONSE(409, 'ERR_PROFILE_NOT_COMPLETE', L_LANG);
         RETURN 409;
      END IF;

      ------------------------------------------------------------------
      -- If Potential Customer => Convert to Real Customer
      ------------------------------------------------------------------
      IF L_POT_CUST_ID IS NOT NULL THEN
         ABSH_API_UTIL_PKG.CONVERT_POTENTIAL_TO_CUSTOMER(L_USER_ID);

         L_CUST_ID   := NULL;
         L_CUST_TYPE := NULL;
         ABSH_API_UTIL_PKG.GET_CUSTOMER_INFO(L_USER_ID, L_CUST_ID, L_CUST_TYPE);

         IF NVL(L_CUST_TYPE, 'X') != 'CUSTOMER' THEN
            ABSH_API_UTIL_PKG.ERROR_RESPONSE(500, 'ERR_CONVERSION_FAILED', L_LANG);
            RETURN 500;
         END IF;

         L_CUSTOMER_ID := L_CUST_ID;
         L_POT_CUST_ID := NULL; -- Ignore -- clear potential flag
      END IF;

      ------------------------------------------------------------------
      -- Get custSiteId (same logic for both real & converted customer)
      ------------------------------------------------------------------
      BEGIN
         SELECT TO_CHAR(SUB.CUST_SITE_ID)
           INTO L_CUST_SITE_ID
           FROM (SELECT SIT.CUST_SITE_ID
                   FROM AR_CUSTOMER_SITE SIT
                   JOIN AR_CUSTOMER C ON C.CUSTOMER_ID = SIT.CUSTOMER_ID
                  WHERE SIT.CUSTOMER_ID = L_CUSTOMER_ID
                    AND (C.CUSTOMER_TYPE LIKE '%PERSON%' OR C.CUSTOMER_TYPE LIKE '%MEDIATION%')
                  ORDER BY SIT.CREATION_DATE DESC NULLS LAST) SUB
          WHERE ROWNUM = 1;
      EXCEPTION
         WHEN NO_DATA_FOUND THEN
            L_CUST_SITE_ID := NULL;
      END;
      IF L_CUST_SITE_ID IS NULL THEN
         ABSH_API_UTIL_PKG.ERROR_RESPONSE(403, 'ERR_CUST_SITE_NOT_FOUND', L_LANG);
         RETURN 403;
      END IF;
      ------------------------------------------------------------------
      -- Validate combination code exists
      ------------------------------------------------------------------
      DECLARE
         L_COMB_COUNT NUMBER;
      BEGIN
         SELECT COUNT(*)
           INTO L_COMB_COUNT
           FROM ABSH_MAIN_PACKAGE_PRICING_OPTIONS
          WHERE INDV_SAL_QUOT_ID = L_PACKAGE_ID
            AND COMBINATION_CODE = L_COMBINATION_CODE;

         IF L_COMB_COUNT = 0 THEN
            ABSH_API_UTIL_PKG.ERROR_RESPONSE(403,
                                             'ERR_COMBINATION_NOT_FOUND',
                                             L_LANG,
                                             APEX_T_VARCHAR2('COMBINATION_CODE', L_COMBINATION_CODE));
            RETURN 403;
         END IF;
      END;
      ------------------------------------------------------------------
      BEGIN
         SELECT S.PRICE
               ,Q.SAL_PRICE
               ,SUBSTR(JSON_VALUE(S.JSON_DATA, '$.SHIFT_TIME'), 1, 5)
               ,SUBSTR(JSON_VALUE(S.JSON_DATA, '$.SHIFT_TIME'), 7, 5)
               ,D.ALLOWED_DAYS
               ,Q.VALID_DATE_FROM
               ,Q.VALID_DATE_TO
           INTO L_TOTAL_PRICE
               ,L_QUOT_PRICE
               ,L_START_TIME
               ,L_END_TIME
               ,L_ALLOWED_DAYS
               ,L_VALID_DATE_FROM
               ,L_VALID_DATE_TO
           FROM ABSH_MAIN_PACKAGE_PRICING_OPTIONS S
           JOIN INDV_SAL_QUOTATION Q ON S.INDV_SAL_QUOT_ID = Q.INDV_SAL_QUOT_ID
           JOIN INDV_SAL_QUOTATION_DETAILS D ON D.INDV_SAL_QUOT_ID = Q.INDV_SAL_QUOT_ID
          WHERE Q.INDV_SAL_QUOT_ID = L_PACKAGE_ID
            AND S.COMBINATION_CODE = L_COMBINATION_CODE;
         ------------------------------------------------------------------
         FOR REC IN (SELECT JT.VISIT_DATE_VAL, TO_DATE(JT.VISIT_DATE_VAL, 'DD/MM/YYYY') AS VISIT_DT
                       FROM JSON_TABLE(L_VISIT_DATA_JSON, '$[*]' COLUMNS(VISIT_DATE_VAL VARCHAR2(20) PATH '$.date')) JT) LOOP

            IF REC.VISIT_DT < L_VALID_DATE_FROM OR REC.VISIT_DT > L_VALID_DATE_TO THEN
               ABSH_API_UTIL_PKG.ERROR_RESPONSE(400,
                                                'ERR_DATE_OUT_OF_RANGE',
                                                L_LANG,
                                                APEX_T_VARCHAR2('DATE',
                                                                REC.VISIT_DATE_VAL,
                                                                'FROM',
                                                                TO_CHAR(L_VALID_DATE_FROM, 'DD/MM/YYYY'),
                                                                'TO',
                                                                TO_CHAR(L_VALID_DATE_TO, 'DD/MM/YYYY')));
               RETURN 400;
            END IF;

            DECLARE
               L_DAY_EN    VARCHAR2(20);
               L_DAY_COUNT NUMBER;
            BEGIN
               L_DAY_EN := TRIM(TO_CHAR(REC.VISIT_DT, 'Day', 'NLS_DATE_LANGUAGE=AMERICAN'));
               SELECT COUNT(*)
                 INTO L_DAY_COUNT
                 FROM JSON_TABLE(L_ALLOWED_DAYS, '$[*]' COLUMNS(DAY_NAME VARCHAR2(20) PATH '$')) JD
                WHERE UPPER(JD.DAY_NAME) = UPPER(L_DAY_EN);

               IF L_DAY_COUNT = 0 THEN
                  ABSH_API_UTIL_PKG.ERROR_RESPONSE(400,
                                                   'ERR_DAY_NOT_ALLOWED',
                                                   L_LANG,
                                                   APEX_T_VARCHAR2('DATE', REC.VISIT_DATE_VAL, 'DAY', L_DAY_EN));
                  RETURN 400;
               END IF;
            END;

         END LOOP;

      EXCEPTION
         WHEN NO_DATA_FOUND THEN
            ABSH_API_UTIL_PKG.ERROR_RESPONSE(403, 'ERR_PACKAGE_NOT_FOUND', L_LANG);
            RETURN 403;
         WHEN OTHERS THEN
            ABSH_API_UTIL_PKG.ERROR_RESPONSE(400, 'ERR_VALIDATION_FAILED', L_LANG, APEX_T_VARCHAR2('MESSAGE', SQLERRM));
            RETURN 400;
      END;

      ------------------------------------------------------------------
      ------------------------------------------------------------------
      BEGIN
         SELECT JSON_ARRAYAGG(JSON_OBJECT('day' VALUE TO_CHAR(TO_DATE(JT.VISIT_DATE_VAL, 'DD/MM/YYYY'),
                                                  'DAY',
                                                  'NLS_DATE_LANGUAGE=ARABIC'),
                                          'day_en' VALUE TRIM(TO_CHAR(TO_DATE(JT.VISIT_DATE_VAL, 'DD/MM/YYYY'),
                                                       'Day',
                                                       'NLS_DATE_LANGUAGE=AMERICAN')),
                                          'date' VALUE JT.VISIT_DATE_VAL,
                                          'startTime' VALUE L_START_TIME,
                                          'endTime' VALUE L_END_TIME NULL ON NULL RETURNING CLOB))
           INTO L_VISIT_DATA_JSON
           FROM JSON_TABLE(L_VISIT_DATA_JSON, '$[*]' COLUMNS(VISIT_DATE_VAL VARCHAR2(20) PATH '$.date')) JT;
      EXCEPTION
         WHEN OTHERS THEN
            ABSH_API_UTIL_PKG.ERROR_RESPONSE(400,
                                             'ERR_visitDataJson_FAILED',
                                             L_LANG,
                                             APEX_T_VARCHAR2('MESSAGE', 'Failed to get visitDataJson'));
            RETURN 400;
      END;

      ------------------------------------------------------------------
      -- Convert date format to safe format (DD-MON-YYYY)
      ------------------------------------------------------------------
      BEGIN
         SELECT JSON_ARRAYAGG(JSON_OBJECT('day' VALUE JT.VISIT_DAY,
                                          'day_en' VALUE JT.VISIT_DAY_EN,
                                          'date' VALUE TO_CHAR(TO_DATE(JT.VISIT_DATE, 'DD/MM/YYYY'),
                                                  'DD-MON-YYYY',
                                                  'NLS_DATE_LANGUAGE=AMERICAN'),
                                          'startTime' VALUE JT.START_TIME,
                                          'endTime' VALUE JT.END_TIME NULL ON NULL RETURNING CLOB))
           INTO L_VISIT_DATA_JSON
           FROM JSON_TABLE(L_VISIT_DATA_JSON,


                           '$[*]' COLUMNS(VISIT_DAY VARCHAR2(50) PATH '$.day',
                                   VISIT_DAY_EN VARCHAR2(50) PATH '$.day_en',
                                   VISIT_DATE VARCHAR2(20) PATH '$.date',
                                   START_TIME VARCHAR2(20) PATH '$.startTime',
                                   END_TIME VARCHAR2(20) PATH '$.endTime')) JT;
      EXCEPTION
         WHEN OTHERS THEN
            ABSH_API_UTIL_PKG.ERROR_RESPONSE(400,
                                             'ERR_INVALID_DATE_FORMAT',
                                             L_LANG,
                                             APEX_T_VARCHAR2('MESSAGE', 'visitDataJson date must be DD/MM/YYYY'));
            RETURN 400;
      END;

      ------------------------------------------------------------------
      -- Step 1: Create Initial RFQ
      ------------------------------------------------------------------
      V_STEP := 'CREATE_INITIAL_RFQ';
      BEGIN
         ABSH_CREATE_ORDER.CREATE_INITIAL_RFQ(P_CUST_SITE_ID     => L_CUST_SITE_ID,
                                              P_CUSTOMER_ID      => L_CUSTOMER_ID,
                                              P_PACKAGE_ID       => L_PACKAGE_ID,
                                              P_COMBINATION_CODE => L_COMBINATION_CODE,
                                              P_TOTAL_PRICE      => L_TOTAL_PRICE,
                                              P_QUOT_PRICE       => L_QUOT_PRICE,
                                              P_VISIT_DATA_JSON  => L_VISIT_DATA_JSON,
                                              P_ADDRESS_ID       => L_ORDER_ADDRESS_ID,
                                              P_ACTION_USER      => L_USER_ID,
                                              P_WITH_OUT_DET     => L_WITH_OUT_DET,
                                              P_RFQ_ID           => V_RFQ_ID,
                                              P_STATUS           => V_STATUS,
                                              P_MESSAGE          => V_MESSAGE);
      END;

      IF NVL(V_STATUS, 'ERROR') != 'SUCCESS' THEN
         ABSH_API_UTIL_PKG.LOG_ERROR(P_ERROR_MESSAGE => 'ABSH_CREATE_ORDER.CREATE_INITIAL_RFQ returned status ' ||
                                                        NVL(V_STATUS, 'NULL') || ' | MESSAGE=' ||
                                                        NVL(SUBSTR(V_MESSAGE, 1, 1000), 'NULL'),
                                     P_ERROR_CODE    => -20001,
                                     P_ERROR_STACK   => 'STEP=' || NVL(V_STEP, 'UNKNOWN') || ' | RFQ_ID=' ||
                                                        NVL(TO_CHAR(V_RFQ_ID), 'NULL') || ' | CUSTOMER_ID=' ||
                                                        NVL(TO_CHAR(L_CUSTOMER_ID), 'NULL') || ' | PACKAGE_ID=' ||
                                                        NVL(TO_CHAR(L_PACKAGE_ID), 'NULL') || ' | COMBINATION_CODE=' ||
                                                        NVL(L_COMBINATION_CODE, 'NULL'),
                                     P_CALLING_PROC  => 'ABSH_API_PRIVATE_PKG.CREATE_ORDER_HOURLY',
                                     P_TABLE_NAME    => 'CREATE_ORDER_HOURLY');

         ABSH_API_UTIL_PKG.ERROR_RESPONSE(400,
                                          'ERR_CREATE_RFQ_FAILED',
                                          L_LANG,
                                          APEX_T_VARCHAR2('MESSAGE',
                                                          NVL(SUBSTR(V_MESSAGE, 1, 1000), 'ERR_CREATE_RFQ_FAILED')));
         RETURN 400;
      END IF;
      ------------------------------------------------------------------
      -- Step 2: Complete Contract After Payment
      ------------------------------------------------------------------
      V_STEP := 'COMPLETE_CONTRACT_AFTER_PAYMENT';

      BEGIN
         ABSH_CREATE_ORDER.COMPLETE_CONTRACT_AFTER_PAYMENT(P_RFQ_ID            => V_RFQ_ID,
                                                           P_PAYMENT_STATUS    => 'SUCCESS',
                                                           P_PAYMENT_REFERENCE => 'PENDING-' || V_RFQ_ID,
                                                           P_CONTRACT_SYMBOL   => V_CONTRACT_SYMBOL,
                                                           P_STATUS            => V_STATUS,
                                                           P_MESSAGE           => V_MESSAGE);
      END;

      IF NVL(V_STATUS, 'ERROR') != 'SUCCESS' THEN
         ABSH_API_UTIL_PKG.LOG_ERROR(P_ERROR_MESSAGE => 'ABSH_CREATE_ORDER.COMPLETE_CONTRACT_AFTER_PAYMENT returned status ' ||
                                                        NVL(V_STATUS, 'NULL') || ' | MESSAGE=' ||
                                                        NVL(SUBSTR(V_MESSAGE, 1, 1000), 'NULL'),
                                     P_ERROR_CODE    => -20002,
                                     P_ERROR_STACK   => 'STEP=' || NVL(V_STEP, 'UNKNOWN') || ' | RFQ_ID=' ||
                                                        NVL(TO_CHAR(V_RFQ_ID), 'NULL') || ' | CONTRACT_SYMBOL=' ||
                                                        NVL(V_CONTRACT_SYMBOL, 'NULL') || ' | CUSTOMER_ID=' ||
                                                        NVL(TO_CHAR(L_CUSTOMER_ID), 'NULL') || ' | PACKAGE_ID=' ||
                                                        NVL(TO_CHAR(L_PACKAGE_ID), 'NULL'),
                                     P_CALLING_PROC  => 'ABSH_API_PRIVATE_PKG.CREATE_ORDER_HOURLY',
                                     P_TABLE_NAME    => 'CREATE_ORDER_HOURLY');


         ABSH_API_UTIL_PKG.ERROR_RESPONSE(400,
                                          'ERR_CREATE_CONTRACT_FAILED',
                                          L_LANG,
                                          APEX_T_VARCHAR2('MESSAGE',
                                                          NVL(SUBSTR(V_MESSAGE, 1, 1000), 'ERR_CREATE_CONTRACT_FAILED')));

         RETURN 400;
      END IF;

      ------------------------------------------------------------------
      -- Build response data
      ------------------------------------------------------------------
      FOR I IN (SELECT RFQ_SYMBOL FROM INDV_SAL_RFQ ISQ WHERE ISQ.INDV_RFQ_ID = V_RFQ_ID) LOOP
         L_RFQ_SYMBOL := I.RFQ_SYMBOL;

      END LOOP;
      SELECT JSON_OBJECT('rfqId' VALUE V_RFQ_ID,
                         'contractSymbol' VALUE V_CONTRACT_SYMBOL,
                         'orderNumber' VALUE L_RFQ_SYMBOL NULL ON NULL RETURNING CLOB)
        INTO L_DATA
        FROM DUAL;

      ------------------------------------------------------------------
      -- Build success response
      ------------------------------------------------------------------
      ABSH_API_UTIL_PKG.SUCCESS_RESPONSE(P_MESSAGE_KEY => 'ORDER_CREATED',
                                         P_LANG        => L_LANG,
                                         P_DATA        => L_DATA,
                                         P_PARAMS      => APEX_T_VARCHAR2('ORDER_ID', L_RFQ_SYMBOL));

      RETURN 200;

   EXCEPTION
      WHEN OTHERS THEN

         ABSH_API_UTIL_PKG.LOG_ERROR(P_ERROR_MESSAGE => SQLERRM,
                                     P_ERROR_CODE    => SQLCODE,
                                     P_ERROR_STACK   => DBMS_UTILITY.FORMAT_ERROR_BACKTRACE,
                                     P_CALLING_PROC  => 'ABSH_API_PRIVATE_PKG.CREATE_ORDER_HOURLY',
                                     P_TABLE_NAME    => 'CREATE_ORDER_HOURLY');

         ABSH_API_UTIL_PKG.ERROR_RESPONSE(P_STATUS_CODE => 500, P_MESSAGE_KEY => 'ERR_INTERNAL', P_LANG => L_LANG);

         RETURN 500;

   END CREATE_ORDER_HOURLY;

   /*  FUNCTION CREATE_ORDER_HOURLY(P_PAYLOAD_JSON IN CLOB) RETURN NUMBER IS
      ------------------------------------------------------------------
      -- Variables
      ------------------------------------------------------------------
      L_LANG             VARCHAR2(10);
      L_CUST_SITE_ID     VARCHAR2(100);
      L_CUSTOMER_ID      NUMBER;
      L_POT_CUST_ID      NUMBER;
      L_CUST_ID          NUMBER;
      L_CUST_TYPE        VARCHAR2(200);
      L_PACKAGE_ID       NUMBER;
      L_COMBINATION_CODE VARCHAR2(500);
      L_PROMOCODE        VARCHAR2(100);
      L_TOTAL_PRICE      NUMBER;
      L_QUOT_PRICE       NUMBER;
      L_VISIT_DATA_JSON  CLOB;
      L_ORDER_ADDRESS_ID NUMBER;
      L_WITH_OUT_DET     VARCHAR2(1);
      L_TOKEN            VARCHAR2(1000);
      L_USER_ID          NUMBER;
      V_RFQ_ID           NUMBER;
      V_CONTRACT_SYMBOL  VARCHAR2(3000);
      V_STATUS           VARCHAR2(500);
      V_MESSAGE          CLOB;
      V_STEP             VARCHAR2(200);
      L_DATA             CLOB;
      L_START_TIME       VARCHAR2(100);
      L_END_TIME         VARCHAR2(100);
      L_ALLOWED_DAYS     CLOB;
      L_VALID_DATE_FROM  DATE;
      L_VALID_DATE_TO    DATE;

   BEGIN
      ------------------------------------------------------------------
      -- Parse JSON input
      ------------------------------------------------------------------
      L_LANG             := NVL(JSON_VALUE(P_PAYLOAD_JSON, '$.acceptLanguage'), C_DEFAULT_LANG);
      L_PACKAGE_ID       := JSON_VALUE(P_PAYLOAD_JSON, '$.packageId');
      L_COMBINATION_CODE := JSON_VALUE(P_PAYLOAD_JSON, '$.combinationCode');
      L_VISIT_DATA_JSON  := JSON_QUERY(P_PAYLOAD_JSON, '$.visitDataJson');
      L_ORDER_ADDRESS_ID := JSON_VALUE(P_PAYLOAD_JSON, '$.orderAddressId');
      L_PROMOCODE        := JSON_VALUE(P_PAYLOAD_JSON, '$.promoCode'); -- Ignore
      L_WITH_OUT_DET     := 'N';
      L_TOKEN            := ABSH_API_UTIL_PKG.GET_BEARER_TOKEN;
      ------------------------------------------------------------------
      -- Validate token
      ------------------------------------------------------------------
      IF L_TOKEN IS NULL THEN
         ABSH_API_UTIL_PKG.ERROR_RESPONSE(400, 'ERR_MISSING_PARAM', L_LANG, APEX_T_VARCHAR2('NAME', 'token'));
         RETURN 400;
      END IF;

      ------------------------------------------------------------------
      -- Validate mandatory parameters
      ------------------------------------------------------------------
      IF L_PACKAGE_ID IS NULL THEN
         ABSH_API_UTIL_PKG.ERROR_RESPONSE(400, 'ERR_MISSING_PARAM', L_LANG, APEX_T_VARCHAR2('NAME', 'packageId'));
         RETURN 400;
      END IF;

      IF L_ORDER_ADDRESS_ID IS NULL THEN
         ABSH_API_UTIL_PKG.ERROR_RESPONSE(400, 'ERR_MISSING_PARAM', L_LANG, APEX_T_VARCHAR2('NAME', 'orderAddressId'));
         RETURN 400;
      END IF;

      ABSH_API_UTIL_PKG.VALIDATE_API_KEY(ABSH_API_UTIL_PKG.GET_APIKEY);

      ------------------------------------------------------------------
      -- Validate JWT and get user ID
      ------------------------------------------------------------------
      L_USER_ID := ABSH_API_PRIVATE_PKG.VALIDATE_JWT_AND_GET_USER_ID(L_TOKEN);
      ABSH_API_UTIL_PKG.VALIDATE_USER_EXISTS(L_USER_ID);

      ------------------------------------------------------------------
      -- Get Customer Info from JWT
      ------------------------------------------------------------------
      ABSH_API_UTIL_PKG.GET_CUSTOMER_INFO(L_USER_ID, L_CUST_ID, L_CUST_TYPE);

      IF L_CUST_TYPE = 'CUSTOMER' THEN
         L_CUSTOMER_ID := L_CUST_ID;
      ELSIF L_CUST_TYPE = 'POTENTIAL' THEN
         L_POT_CUST_ID := L_CUST_ID;
      END IF;

      IF L_CUSTOMER_ID IS NULL AND L_POT_CUST_ID IS NULL THEN
         ABSH_API_UTIL_PKG.ERROR_RESPONSE(403, 'ERR_USER_NOT_FOUND', L_LANG);
         RETURN 403;
      END IF;

      ------------------------------------------------------------------
      -- Check and validate customer profile
      ------------------------------------------------------------------
      IF ABSH_API_UTIL_PKG.IS_PROFILE_COMPLETE(L_USER_ID) = 0 THEN
         ABSH_API_UTIL_PKG.ERROR_RESPONSE(409, 'ERR_PROFILE_NOT_COMPLETE', L_LANG);
         RETURN 409;
      END IF;

      ------------------------------------------------------------------
      -- If Potential Customer => Convert to Real Customer
      ------------------------------------------------------------------
      IF L_POT_CUST_ID IS NOT NULL THEN
         ABSH_API_UTIL_PKG.CONVERT_POTENTIAL_TO_CUSTOMER(L_USER_ID);

         L_CUST_ID   := NULL;
         L_CUST_TYPE := NULL;
         ABSH_API_UTIL_PKG.GET_CUSTOMER_INFO(L_USER_ID, L_CUST_ID, L_CUST_TYPE);

         IF NVL(L_CUST_TYPE, 'X') != 'CUSTOMER' THEN

            ABSH_API_UTIL_PKG.ERROR_RESPONSE(500, 'ERR_CONVERSION_FAILED', L_LANG);
            RETURN 500;
         END IF;

         L_CUSTOMER_ID := L_CUST_ID;
         L_POT_CUST_ID := NULL; -- Ignore -- clear potential flag
      END IF;

      ------------------------------------------------------------------
      -- Get custSiteId (same logic for both real & converted customer)
      ------------------------------------------------------------------
      BEGIN
         SELECT TO_CHAR(SUB.CUST_SITE_ID)
           INTO L_CUST_SITE_ID
           FROM (SELECT SIT.CUST_SITE_ID
                   FROM AR_CUSTOMER_SITE SIT
                   JOIN AR_CUSTOMER C ON C.CUSTOMER_ID = SIT.CUSTOMER_ID
                  WHERE SIT.CUSTOMER_ID = L_CUSTOMER_ID
                    AND (C.CUSTOMER_TYPE LIKE '%PERSON%' OR C.CUSTOMER_TYPE LIKE '%MEDIATION%')
                  ORDER BY SIT.CREATION_DATE DESC NULLS LAST) SUB
          WHERE ROWNUM = 1;
      EXCEPTION
         WHEN NO_DATA_FOUND THEN
            L_CUST_SITE_ID := NULL;
      END;
      IF L_CUST_SITE_ID IS NULL THEN
         ABSH_API_UTIL_PKG.ERROR_RESPONSE(403, 'ERR_CUST_SITE_NOT_FOUND', L_LANG);
         RETURN 403;
      END IF;
      ------------------------------------------------------------------
      -- Validate combination code exists
      ------------------------------------------------------------------
      DECLARE
         L_COMB_COUNT NUMBER;
      BEGIN
         SELECT COUNT(*)
           INTO L_COMB_COUNT
           FROM ABSH_MAIN_PACKAGE_PRICING_OPTIONS
          WHERE INDV_SAL_QUOT_ID = L_PACKAGE_ID
            AND COMBINATION_CODE = L_COMBINATION_CODE;

         IF L_COMB_COUNT = 0 THEN
            ABSH_API_UTIL_PKG.ERROR_RESPONSE(403,
                                             'ERR_COMBINATION_NOT_FOUND',
                                             L_LANG,
                                             APEX_T_VARCHAR2('COMBINATION_CODE', L_COMBINATION_CODE));
            RETURN 403;
         END IF;
      END;
      ------------------------------------------------------------------
      BEGIN
         SELECT S.PRICE
               ,Q.SAL_PRICE
               ,SUBSTR(JSON_VALUE(S.JSON_DATA, '$.SHIFT_TIME'), 1, 5)
               ,SUBSTR(JSON_VALUE(S.JSON_DATA, '$.SHIFT_TIME'), 7, 5)
               ,D.ALLOWED_DAYS
               ,Q.VALID_DATE_FROM
               ,Q.VALID_DATE_TO
           INTO L_TOTAL_PRICE
               ,L_QUOT_PRICE
               ,L_START_TIME
               ,L_END_TIME
               ,L_ALLOWED_DAYS
               ,L_VALID_DATE_FROM
               ,L_VALID_DATE_TO
           FROM ABSH_MAIN_PACKAGE_PRICING_OPTIONS S
           JOIN INDV_SAL_QUOTATION Q ON S.INDV_SAL_QUOT_ID = Q.INDV_SAL_QUOT_ID
           JOIN INDV_SAL_QUOTATION_DETAILS D ON D.INDV_SAL_QUOT_ID = Q.INDV_SAL_QUOT_ID
          WHERE Q.INDV_SAL_QUOT_ID = L_PACKAGE_ID
            AND S.COMBINATION_CODE = L_COMBINATION_CODE;
         ------------------------------------------------------------------
         FOR REC IN (SELECT JT.VISIT_DATE_VAL, TO_DATE(JT.VISIT_DATE_VAL, 'DD/MM/YYYY') AS VISIT_DT
                       FROM JSON_TABLE(L_VISIT_DATA_JSON, '$[*]' COLUMNS(VISIT_DATE_VAL VARCHAR2(20) PATH '$.date')) JT) LOOP

            IF REC.VISIT_DT < L_VALID_DATE_FROM OR REC.VISIT_DT > L_VALID_DATE_TO THEN
               ABSH_API_UTIL_PKG.ERROR_RESPONSE(400,
                                                'ERR_DATE_OUT_OF_RANGE',
                                                L_LANG,
                                                APEX_T_VARCHAR2('DATE',
                                                                REC.VISIT_DATE_VAL,
                                                                'FROM',
                                                                TO_CHAR(L_VALID_DATE_FROM, 'DD/MM/YYYY'),
                                                                'TO',
                                                                TO_CHAR(L_VALID_DATE_TO, 'DD/MM/YYYY')));
               RETURN 400;
            END IF;

            DECLARE
               L_DAY_EN    VARCHAR2(20);
               L_DAY_COUNT NUMBER;
            BEGIN
               L_DAY_EN := TRIM(TO_CHAR(REC.VISIT_DT, 'Day', 'NLS_DATE_LANGUAGE=AMERICAN'));
               SELECT COUNT(*)
                 INTO L_DAY_COUNT
                 FROM JSON_TABLE(L_ALLOWED_DAYS, '$[*]' COLUMNS(DAY_NAME VARCHAR2(20) PATH '$')) JD
                WHERE UPPER(JD.DAY_NAME) = UPPER(L_DAY_EN);

               IF L_DAY_COUNT = 0 THEN
                  ABSH_API_UTIL_PKG.ERROR_RESPONSE(400,
                                                   'ERR_DAY_NOT_ALLOWED',
                                                   L_LANG,
                                                   APEX_T_VARCHAR2('DATE', REC.VISIT_DATE_VAL, 'DAY', L_DAY_EN));
                  RETURN 400;
               END IF;
            END;

         END LOOP;

      EXCEPTION
         WHEN NO_DATA_FOUND THEN
            ABSH_API_UTIL_PKG.ERROR_RESPONSE(403, 'ERR_PACKAGE_NOT_FOUND', L_LANG);
            RETURN 403;
         WHEN OTHERS THEN
            ABSH_API_UTIL_PKG.ERROR_RESPONSE(400, 'ERR_VALIDATION_FAILED', L_LANG, APEX_T_VARCHAR2('MESSAGE', SQLERRM));
            RETURN 400;
      END;

      ------------------------------------------------------------------
      ------------------------------------------------------------------
      BEGIN
         SELECT JSON_ARRAYAGG(JSON_OBJECT('day' VALUE TO_CHAR(TO_DATE(JT.VISIT_DATE_VAL, 'DD/MM/YYYY'),
                                                  'DAY',
                                                  'NLS_DATE_LANGUAGE=ARABIC'),
                                          'day_en' VALUE TRIM(TO_CHAR(TO_DATE(JT.VISIT_DATE_VAL, 'DD/MM/YYYY'),
                                                       'Day',
                                                       'NLS_DATE_LANGUAGE=AMERICAN')),
                                          'date' VALUE JT.VISIT_DATE_VAL,
                                          'startTime' VALUE L_START_TIME,
                                          'endTime' VALUE L_END_TIME NULL ON NULL RETURNING CLOB))
           INTO L_VISIT_DATA_JSON
           FROM JSON_TABLE(L_VISIT_DATA_JSON, '$[*]' COLUMNS(VISIT_DATE_VAL VARCHAR2(20) PATH '$.date')) JT;
      EXCEPTION
         WHEN OTHERS THEN
            ABSH_API_UTIL_PKG.ERROR_RESPONSE(400,
                                             'ERR_visitDataJson_FAILED',
                                             L_LANG,
                                             APEX_T_VARCHAR2('MESSAGE', 'Failed to get visitDataJson'));
            RETURN 400;
      END;

      ------------------------------------------------------------------
      -- Convert date format to safe format (DD-MON-YYYY)
      ------------------------------------------------------------------
      BEGIN
         SELECT JSON_ARRAYAGG(JSON_OBJECT('day' VALUE JT.VISIT_DAY,
                                          'day_en' VALUE JT.VISIT_DAY_EN,
                                          'date' VALUE TO_CHAR(TO_DATE(JT.VISIT_DATE, 'DD/MM/YYYY'),
                                                  'DD-MON-YYYY',
                                                  'NLS_DATE_LANGUAGE=AMERICAN'),
                                          'startTime' VALUE JT.START_TIME,
                                          'endTime' VALUE JT.END_TIME NULL ON NULL RETURNING CLOB))
           INTO L_VISIT_DATA_JSON
           FROM JSON_TABLE(L_VISIT_DATA_JSON,
                           '$[*]' COLUMNS(VISIT_DAY VARCHAR2(50) PATH '$.day',
                                   VISIT_DAY_EN VARCHAR2(50) PATH '$.day_en',
                                   VISIT_DATE VARCHAR2(20) PATH '$.date',
                                   START_TIME VARCHAR2(20) PATH '$.startTime',
                                   END_TIME VARCHAR2(20) PATH '$.endTime')) JT;
      EXCEPTION
         WHEN OTHERS THEN
            ABSH_API_UTIL_PKG.ERROR_RESPONSE(400,
                                             'ERR_INVALID_DATE_FORMAT',
                                             L_LANG,
                                             APEX_T_VARCHAR2('MESSAGE', 'visitDataJson date must be DD/MM/YYYY'));
            RETURN 400;
      END;

      ------------------------------------------------------------------
      -- Step 1: Create Initial RFQ
      ------------------------------------------------------------------
      V_STEP := 'CREATE_INITIAL_RFQ';
      BEGIN
         ABSH_CREATE_ORDER.CREATE_INITIAL_RFQ(P_CUST_SITE_ID     => L_CUST_SITE_ID,
                                              P_CUSTOMER_ID      => L_CUSTOMER_ID,
                                              P_PACKAGE_ID       => L_PACKAGE_ID,
                                              P_COMBINATION_CODE => L_COMBINATION_CODE,
                                              P_TOTAL_PRICE      => L_TOTAL_PRICE,
                                              P_QUOT_PRICE       => L_QUOT_PRICE,
                                              P_VISIT_DATA_JSON  => L_VISIT_DATA_JSON,
                                              P_ADDRESS_ID       => L_ORDER_ADDRESS_ID,
                                              P_ACTION_USER      => L_USER_ID,
                                              P_WITH_OUT_DET     => L_WITH_OUT_DET,
                                              P_RFQ_ID           => V_RFQ_ID,
                                              P_STATUS           => V_STATUS,
                                              P_MESSAGE          => V_MESSAGE);
      END;

      --    IF NVL(V_STATUS, 'ERROR') != 'SUCCESS' THEN
      --       ABSH_API_UTIL_PKG.ERROR_RESPONSE(400, V_MESSAGE, L_LANG,
      --                                        APEX_T_VARCHAR2('MESSAGE', NVL(V_MESSAGE, 'ERR_CREATE_RFQ_FAILED')));
      --       RETURN 400;
      --    END IF;
      IF NVL(V_STATUS, 'ERROR') != 'SUCCESS' THEN
         ABSH_API_UTIL_PKG.ERROR_RESPONSE(400, 'ERR_CREATE_RFQ_FAILED', L_LANG);
         RETURN 400;
      END IF;
      ------------------------------------------------------------------
      -- Step 2: Complete Contract After Payment
      ------------------------------------------------------------------
      V_STEP := 'COMPLETE_CONTRACT_AFTER_PAYMENT';

      BEGIN
         ABSH_CREATE_ORDER.COMPLETE_CONTRACT_AFTER_PAYMENT(P_RFQ_ID            => V_RFQ_ID,
                                                           P_PAYMENT_STATUS    => 'SUCCESS',
                                                           P_PAYMENT_REFERENCE => 'PENDING-' || V_RFQ_ID,
                                                           P_CONTRACT_SYMBOL   => V_CONTRACT_SYMBOL,
                                                           P_STATUS            => V_STATUS,
                                                           P_MESSAGE           => V_MESSAGE);
      END;

      --    IF NVL(V_STATUS, 'ERROR') != 'SUCCESS' THEN
      --       ABSH_API_UTIL_PKG.ERROR_RESPONSE(400, SUBSTR(V_MESSAGE, 1, 200), L_LANG,
      --                                        APEX_T_VARCHAR2('MESSAGE', NVL(SUBSTR(V_MESSAGE, 1, 200), 'ERR_CREATE_CONTRACT_FAILED')));
      --       RETURN 400;
      --    END IF;
      IF NVL(V_STATUS, 'ERROR') != 'SUCCESS' THEN
         ABSH_API_UTIL_PKG.ERROR_RESPONSE(400, 'ERR_CREATE_CONTRACT_FAILED', L_LANG);
         RETURN 400;
      END IF;

      ------------------------------------------------------------------
      -- Build response data
      ------------------------------------------------------------------
      SELECT JSON_OBJECT('rfqId' VALUE V_RFQ_ID, 'contractSymbol' VALUE V_CONTRACT_SYMBOL NULL ON NULL RETURNING CLOB)
        INTO L_DATA
        FROM DUAL;

      ------------------------------------------------------------------
      -- Build success response
      ------------------------------------------------------------------
      ABSH_API_UTIL_PKG.SUCCESS_RESPONSE(P_MESSAGE_KEY => 'ORDER_CREATED', P_LANG => L_LANG, P_DATA => L_DATA);

      RETURN 200;

   EXCEPTION
      WHEN OTHERS THEN

         ABSH_API_UTIL_PKG.LOG_ERROR(P_ERROR_MESSAGE => SQLERRM,
                                     P_ERROR_CODE    => SQLCODE,
                                     P_ERROR_STACK   => DBMS_UTILITY.FORMAT_ERROR_BACKTRACE,
                                     P_CALLING_PROC  => 'ABSH_API_PRIVATE_PKG.CREATE_ORDER_HOURLY',
                                     P_TABLE_NAME    => 'CREATE_ORDER_HOURLY');

         ABSH_API_UTIL_PKG.ERROR_RESPONSE(P_STATUS_CODE => 500, P_MESSAGE_KEY => 'ERR_INTERNAL', P_LANG => L_LANG);

         RETURN 500;

      \*EXCEPTION
      WHEN OTHERS THEN
         DECLARE
            V_SQLERRM   VARCHAR2(32767) := SQLERRM;
            V_BACKTRACE VARCHAR2(32767) := DBMS_UTILITY.FORMAT_ERROR_BACKTRACE;
         BEGIN
            INSERT INTO ABSH_EXCEPTION_LOG
               (ERROR_MESSAGE)
            VALUES
               ('CREATE_ORDER API Error | ' || 'STEP: ' || NVL(V_STEP, 'UNKNOWN') || ' | ' || 'RFQ: ' ||
                NVL(TO_CHAR(V_RFQ_ID), 'NULL') || ' | ' || 'CONTRACT: ' || NVL(V_CONTRACT_SYMBOL, 'NULL') || ' | ' ||
                'STATUS: ' || NVL(V_STATUS, 'NULL') || ' | ' || 'MESSAGE: ' || NVL(SUBSTR(V_MESSAGE, 1, 500), 'NULL') ||
                ' | ' || 'ERROR: ' || V_SQLERRM || ' | ' || 'BACKTRACE: ' || V_BACKTRACE);
            COMMIT;
         EXCEPTION
            WHEN OTHERS THEN
               NULL;
         END;

         ABSH_API_UTIL_PKG.ERROR_RESPONSE(500,
                                          'ERR_INTERNAL_ERROR',
                                          L_LANG,
                                          APEX_T_VARCHAR2('ERROR',
                                                          SQLERRM || ' - ' || DBMS_UTILITY.FORMAT_ERROR_BACKTRACE));
         RETURN 500;*\

   END CREATE_ORDER_HOURLY;

   */
   -----------------------------------------------------------------------------------
      FUNCTION CONFIRM_ONLINE_REQUEST(P_PAYLOAD_JSON IN CLOB) RETURN NUMBER IS
      L_TOKEN   VARCHAR2(4000);
      L_LANG    VARCHAR2(10);
      L_USER_ID NUMBER;
      L_DATA    CLOB;
      L_CUST_ID                 NUMBER;
      L_CUST_TYPE               VARCHAR2(50);

      -- Inputs
      L_TERMS_AND_CONDITIONS    VARCHAR2(100);
      L_INDV_SAL_QUOT_ID        NUMBER;
      L_POT_CUST_ID             NUMBER;
      L_CUSTOMER_ID             NUMBER;
      L_ORDER_ADDRESS_ID        NUMBER;
      L_CUSTOMER_IDENT_ID       NUMBER;
      L_WORK_SKILL              NUMBER;
      L_WORKED_BEFORE           VARCHAR2(100);
      L_SALES_CODE              VARCHAR2(100);
      L_EMP_ID                  NUMBER;
      L_SHOWROOM                NUMBER;
      L_REFE_CUST_CONTRACT_ID   NUMBER;
      L_COMBINATION_CODE        VARCHAR2(100);
      L_VISIT_DATA_JSON         CLOB;
      L_ADDRESS_ID              NUMBER;

      -- Business layer results
      V_CONTRACT_SYMBOL         VARCHAR2(100);
      V_CUSTOMER_ID             NUMBER;
      V_SUCC_MSG                VARCHAR2(1000);

      -- Leaked logic variables
      V_ADDRESS_ID              NUMBER;
      V_POT_NAME                VARCHAR2(200);
      V_CUSTOMER_FIRST_NAME     VARCHAR2(100);
      V_CUSTOMER_LAST_NAME      VARCHAR2(100);
   BEGIN
      L_TOKEN := ABSH_API_UTIL_PKG.GET_BEARER_TOKEN;
      L_LANG  := ABSH_API_UTIL_PKG.RESOLVE_LANG(JSON_VALUE(P_PAYLOAD_JSON, '$.acceptLanguage'));

      IF L_TOKEN IS NULL THEN
         ABSH_API_UTIL_PKG.ERROR_RESPONSE(401, 'ERR_UNAUTHORIZED', L_LANG);
         RETURN 401;
      END IF;

      ABSH_API_UTIL_PKG.VALIDATE_API_KEY(ABSH_API_UTIL_PKG.GET_APIKEY);

      -- Authentication
      L_USER_ID := ABSH_API_PRIVATE_PKG.VALIDATE_JWT_AND_GET_USER_ID(L_TOKEN);

      -- Parsing payload
      L_TERMS_AND_CONDITIONS    := JSON_VALUE(P_PAYLOAD_JSON, '$.termsAndConditions');
      L_INDV_SAL_QUOT_ID        := JSON_VALUE(P_PAYLOAD_JSON, '$.packageId' RETURNING NUMBER);
      L_POT_CUST_ID             := JSON_VALUE(P_PAYLOAD_JSON, '$.potentialCustomerId' RETURNING NUMBER);
      L_CUSTOMER_ID             := JSON_VALUE(P_PAYLOAD_JSON, '$.appCustomerId' RETURNING NUMBER);
      L_ORDER_ADDRESS_ID        := NVL(JSON_VALUE(P_PAYLOAD_JSON, '$.orderAddressId' RETURNING NUMBER), JSON_VALUE(P_PAYLOAD_JSON, '$.addressId' RETURNING NUMBER));
      L_CUSTOMER_IDENT_ID       := JSON_VALUE(P_PAYLOAD_JSON, '$.customerIdentId' RETURNING NUMBER);
      L_WORK_SKILL              := JSON_VALUE(P_PAYLOAD_JSON, '$.workSkill' RETURNING NUMBER);
      L_WORKED_BEFORE           := JSON_VALUE(P_PAYLOAD_JSON, '$.workedBefore');
      L_SALES_CODE              := JSON_VALUE(P_PAYLOAD_JSON, '$.salesCode');
      L_EMP_ID                  := JSON_VALUE(P_PAYLOAD_JSON, '$.empId' RETURNING NUMBER);
      L_SHOWROOM                := JSON_VALUE(P_PAYLOAD_JSON, '$.showroom' RETURNING NUMBER);
      L_REFE_CUST_CONTRACT_ID   := JSON_VALUE(P_PAYLOAD_JSON, '$.refCustContractId' RETURNING NUMBER);
      L_COMBINATION_CODE        := JSON_VALUE(P_PAYLOAD_JSON, '$.combinationCode');
      L_VISIT_DATA_JSON         := JSON_VALUE(P_PAYLOAD_JSON, '$.visitData' RETURNING CLOB);
      L_ADDRESS_ID              := NVL(JSON_VALUE(P_PAYLOAD_JSON, '$.orderAddressId' RETURNING NUMBER), JSON_VALUE(P_PAYLOAD_JSON, '$.addressId' RETURNING NUMBER));

      -- Resolve Customer Info via API Utilities
      ABSH_API_UTIL_PKG.GET_CUSTOMER_INFO(L_USER_ID, L_CUST_ID, L_CUST_TYPE);
      IF L_CUST_TYPE = 'CUSTOMER' THEN
         L_CUSTOMER_ID := L_CUST_ID;
      ELSE
         L_POT_CUST_ID := L_CUST_ID;
      END IF;

      V_CUSTOMER_FIRST_NAME     := JSON_VALUE(P_PAYLOAD_JSON, '$.customerFirstName');
      V_CUSTOMER_LAST_NAME      := JSON_VALUE(P_PAYLOAD_JSON, '$.customerLastName');

      -- Light parameter validation
      IF L_TERMS_AND_CONDITIONS IS NULL THEN
         ABSH_API_UTIL_PKG.ERROR_RESPONSE(400, 'ERR_MISSING_PARAM', L_LANG, APEX_T_VARCHAR2('NAME', 'termsAndConditions'));
         RETURN 400;
      END IF;

      -- Potential Customer Address resolution
      IF L_CUSTOMER_ID IS NULL THEN
         ABSH_BUSINESS_PRIVATE_PKG.RESOLVE_POTENTIAL_CUSTOMER_ADDRESS(L_POT_CUST_ID, V_ADDRESS_ID, V_POT_NAME);
         V_CUSTOMER_LAST_NAME := V_POT_NAME;
      ELSE
         V_ADDRESS_ID := L_ORDER_ADDRESS_ID;
      END IF;

      IF V_CUSTOMER_LAST_NAME IS NULL THEN
         V_CUSTOMER_LAST_NAME := V_CUSTOMER_FIRST_NAME;
      END IF;

      -- Execute business logic procedure
      BEGIN
         V_CUSTOMER_ID := L_CUSTOMER_ID;

         ABSH_CREATE_ORDER_PKG.CREATE_LIVEIN_ORDER(
             P_TERMS_AND_CONDITIONS    => L_TERMS_AND_CONDITIONS,
             P_INDV_SAL_QUOT_ID        => L_INDV_SAL_QUOT_ID,
             P_SESSION_POT_CUST_ID     => L_POT_CUST_ID,
             P_CUSTOMER_ID             => V_CUSTOMER_ID,
             P_SESSION_USER_ID         => L_USER_ID,
             P_CUSTOMER_FIRST_NAME     => V_CUSTOMER_FIRST_NAME,
             P_CUSTOMER_LAST_NAME      => V_CUSTOMER_LAST_NAME,
             P_CUSTOMER_ADDRESS        => NVL(V_ADDRESS_ID, L_ORDER_ADDRESS_ID),
             P_CUSTOMER_IDENT_ID       => L_CUSTOMER_IDENT_ID,
             P_WORK_SKILL              => L_WORK_SKILL,
             P_REFE_CUST_CONTRACT_ID   => L_REFE_CUST_CONTRACT_ID,
             P_WORKED_BEFORE           => L_WORKED_BEFORE,
             P_SALES_CODE              => L_SALES_CODE,
             P_EMP_ID                  => L_EMP_ID,
             P_SHOWROOM                => L_SHOWROOM,
             P_COMBINATION_CODE        => L_COMBINATION_CODE,
             P_VISIT_DATA_JSON         => L_VISIT_DATA_JSON,
             P_ADDRESS_ID              => L_ADDRESS_ID,
             P_CONTRACT_SYMBOL         => V_CONTRACT_SYMBOL
         );

         -- Create standard user-facing success message
         V_SUCC_MSG := ABSH_API_UTIL_PKG.TRANSLATE_TEXT(L_LANG, 'Contract Number') || ' ' || V_CONTRACT_SYMBOL || ' ' || ABSH_API_UTIL_PKG.TRANSLATE_TEXT(L_LANG, 'Created Successfully');

         COMMIT;

      EXCEPTION
         WHEN OTHERS THEN
            ROLLBACK;
            ABSH_API_UTIL_PKG.ERROR_RESPONSE(500,
                                             'ERR_CONFIRMATION_FAILED',
                                             L_LANG,
                                             APEX_T_VARCHAR2('ERROR', SQLERRM || ' - ' || DBMS_UTILITY.FORMAT_ERROR_BACKTRACE));
            RETURN 500;
      END;

      -- Build JSON Response (No explicit transaction boundaries; auto-committed by ORDS)
      SELECT JSON_OBJECT('packageId' VALUE L_INDV_SAL_QUOT_ID,
                         'customerId' VALUE NVL(V_CUSTOMER_ID, L_CUSTOMER_ID),
                         'potentialCustomerId' VALUE L_POT_CUST_ID,
                         'appCustomerId' VALUE L_CUSTOMER_ID,
                         'message' VALUE V_SUCC_MSG,
                         'contractSymbol' VALUE V_CONTRACT_SYMBOL,
                         'addressId' VALUE V_ADDRESS_ID,
                         'campLocation' VALUE
                         (SELECT JSON_OBJECT(
                             'name' VALUE L.LOCATION_NAME_L1,
                             'addressText' VALUE DECODE(H.LOC_DESC_L1, NULL, H.ADDRESS, H.LOC_DESC_L1 || DECODE(H.ADDRESS, NULL, '', ' - ' || H.ADDRESS)),
                             'latitude' VALUE L.CMP_LATITUDE,
                             'longitude' VALUE L.CMP_LONGITUDE,
                             'city' VALUE CMP_LOCATIONS_PKG.GET_LOCATION_CITY(L.LOCATION_ID)
                             NULL ON NULL
                           )
                           FROM RUNERP_CUSTDATA.CMP_LOCATIONS L
                           LEFT JOIN RUNERP_CUSTDATA.HR_LOCATION H ON H.LOCATION_ID = L.LOCATION_ID
                           WHERE L.LOCATION_ID = CMP_EMP_LOC_TRANS_PKG.GET_CURRENT_LOCATION_ID(L_EMP_ID)) FORMAT JSON NULL ON NULL RETURNING CLOB)
        INTO L_DATA
        FROM DUAL;

      ABSH_API_UTIL_PKG.SUCCESS_RESPONSE(P_MESSAGE_KEY => 'REQUEST_CONFIRMED', P_LANG => L_LANG, P_DATA => L_DATA);
      RETURN 200;

   EXCEPTION
      WHEN OTHERS THEN
         ROLLBACK;
         ABSH_API_UTIL_PKG.ERROR_RESPONSE(500,
                                          'ERR_INTERNAL_ERROR',
                                          L_LANG,
                                          APEX_T_VARCHAR2('ERROR', SQLERRM || ' - ' || DBMS_UTILITY.FORMAT_ERROR_BACKTRACE));
         RETURN 500;
   END CONFIRM_ONLINE_REQUEST;

   -----------------------------------------------------------------------------------

   ----------------------------------------------------------------------------------------------------------------------
   FUNCTION GET_CUSTOMER_CONTRACTS(P_PAYLOAD_JSON IN CLOB) RETURN NUMBER IS

      ------------------------------------------------------------------
      -- Variables
      ------------------------------------------------------------------
      L_USER_ID                NUMBER;
      L_CUST_ID                NUMBER;
      L_CUST_TYPE              VARCHAR2(200);
      L_CUSTOMER_ID            NUMBER;
      L_POT_CUST_ID            NUMBER;
      L_TOKEN                  VARCHAR2(4000);
      L_LANG                   VARCHAR2(10);
      L_DATA                   CLOB;
      L_CONTRACT_STATUS_FILTER VARCHAR2(50);
      L_PAGE                   NUMBER := NVL(JSON_VALUE(P_PAYLOAD_JSON, '$.page' RETURNING NUMBER), 1);
      L_PAGE_SIZE CONSTANT NUMBER := 30;
      L_OFFSET NUMBER;
   BEGIN

      IF L_PAGE < 1 THEN
         L_PAGE := 1;
      END IF;

      L_OFFSET := (L_PAGE - 1) * L_PAGE_SIZE;
      ------------------------------------------------------------------
      -- Validate request body
      ------------------------------------------------------------------
      IF P_PAYLOAD_JSON IS NULL OR LENGTH(TRIM(P_PAYLOAD_JSON)) = 0 THEN
         ABSH_API_UTIL_PKG.ERROR_RESPONSE(400, 'ERR_MISSING_PARAM', C_DEFAULT_LANG, APEX_T_VARCHAR2('NAME', 'body'));
         RETURN 400;
      END IF;

      ------------------------------------------------------------------
      -- Resolve language
      ------------------------------------------------------------------
      L_LANG := NVL(ABSH_API_UTIL_PKG.RESOLVE_LANG(JSON_VALUE(P_PAYLOAD_JSON, '$.acceptLanguage')), C_DEFAULT_LANG);

      ------------------------------------------------------------------
      -- Extract optional contract status filter
      ------------------------------------------------------------------
      L_CONTRACT_STATUS_FILTER := JSON_VALUE(P_PAYLOAD_JSON, '$.contractStatus');

      ------------------------------------------------------------------
      -- Extract Bearer token
      ------------------------------------------------------------------
      L_TOKEN := ABSH_API_UTIL_PKG.GET_BEARER_TOKEN;

      IF L_TOKEN IS NULL OR LENGTH(TRIM(L_TOKEN)) = 0 THEN
         ABSH_API_UTIL_PKG.ERROR_RESPONSE(400, 'ERR_MISSING_PARAM', L_LANG, APEX_T_VARCHAR2('NAME', 'Authorization'));
         RETURN 400;
      END IF;

      ------------------------------------------------------------------
      -- Validate JWT
      ------------------------------------------------------------------
      L_USER_ID := ABSH_API_PRIVATE_PKG.VALIDATE_JWT_AND_GET_USER_ID(L_TOKEN);

      IF L_USER_ID IS NULL THEN
         ABSH_API_UTIL_PKG.ERROR_RESPONSE(401, 'ERR_UNAUTHORIZED', L_LANG);
         RETURN 401;
      END IF;

      ------------------------------------------------------------------
      -- Resolve customer / potential customer
      ------------------------------------------------------------------
      ABSH_API_UTIL_PKG.GET_CUSTOMER_INFO(L_USER_ID, L_CUST_ID, L_CUST_TYPE);

      IF L_CUST_TYPE = 'CUSTOMER' THEN
         L_CUSTOMER_ID := L_CUST_ID;

      ELSIF L_CUST_TYPE = 'POTENTIAL' THEN
         L_POT_CUST_ID := L_CUST_ID;
      END IF;

      IF L_CUSTOMER_ID IS NULL AND L_POT_CUST_ID IS NULL THEN
         ABSH_API_UTIL_PKG.ERROR_RESPONSE(403,
                                          'ERR_USER_NOT_FOUND Please provide either potentialCustomerId or appCustomerId',
                                          L_LANG);
         RETURN 403;
      END IF;

      ------------------------------------------------------------------
      -- Build contracts JSON using set-based SQL
      ------------------------------------------------------------------
      SELECT CASE
                WHEN COUNT(*) = 0 THEN
                 TO_CLOB('[]')
                ELSE

                 JSON_ARRAYAGG(JSON_OBJECT('contractId' VALUE CUST_CONTRACT_ID,
                                           'orderNumber' VALUE RFQ_SYMBOL,
                                           'contractNo' VALUE CONTR_CONTRACT_NO,
                                           'contractDate' VALUE CONTR_CONTRACT_DATE,
                                           'dateFrom' VALUE CONTR_DATE_FROM,
                                           'dateTo' VALUE CONTR_DATE_TO,
                                           'progressPct' VALUE CONTR_PROGRESS_PCT,
                                           'progressText' VALUE CONTR_PROGRESS_TEXT,
                                           'serviceName' VALUE PACKAGE_NAME,
                                           'nationality' VALUE CONTR_NATIONALITY,
                                           'contractPeriod' VALUE CONTR_CONTRACT_PERIOD,
                                           'statusText' VALUE CONTR_STATUS_TEXT,
                                           'statusFilter' VALUE CONTR_STATUS_FILTER,
                                           'statusCode' VALUE CONTR_STATUS_CODE,
                                           'contractStatus' VALUE CONTRACT_STATUS,
                                           'daysConsumed' VALUE CONTR_DAYS_CONSUMED,
                                           'paymentAwaited' VALUE PAYMENT_AWAITED,
                                           'PackageId' VALUE PACKAGE_ID,
                                           'ratingAspects' VALUE
                                           ABSH_RATING_PKG.GET_RATING_ASPECTS_BY_PACKAGE(PACKAGE_ID, L_LANG) FORMAT JSON,
                                           'workersRating' VALUE
                                           ABSH_RATING_PKG.GET_ORDER_WORKER_RATINGS(RFQ_SYMBOL, P_LANG => L_LANG) FORMAT JSON,
                                           'workerCv' VALUE CASE
                                              WHEN NVL(PACKAGE_TYPE, '_') <> 'HOURLY' THEN
                                               ''
                                           --                                                ABSH_API_UTIL_PKG.GET_WORKER_CARD(P_ID => CUST_CONTRACT_ID, P_LANG => L_LANG, P_BY => 'CONTRACT_ID')
                                           END NULL ON NULL RETURNING CLOB) ORDER BY CUST_CONTRACT_ID DESC RETURNING CLOB)
             END
        INTO L_DATA
        FROM (SELECT *
                FROM (WITH BASE AS (SELECT C.CUST_CONTRACT_ID
                                          ,C.CUST_CONTRACT_SYMBOL
                                          ,C.CUST_CONTRACT_DATE
                                          ,C.EXPIRE_DATE
                                          ,C.CONTRACT_STATUS
                                          ,C.CUSTOMER_ID
                                          ,R.INDV_SAL_QUOT_ID AS PACKAGE_ID
                                          ,Q.NATIONALITY_ID
                                          ,DC.QUOT_DAYS
                                          ,Q.PACKAGE_TYPE
                                          ,C.INDV_RFQ_ID
                                          ,R.RFQ_SYMBOL
                                          ,DECODE(L_LANG, C_DEFAULT_LANG, Q.QUOT_NAME_L1, Q.QUOT_NAME_L2) PACKAGE_NAME


                                      FROM REC_CUST_CONTRACT C
                                      JOIN INDV_SAL_RFQ R ON R.INDV_RFQ_ID = C.INDV_RFQ_ID
                                      LEFT JOIN INDV_SAL_QUOTATION Q ON Q.INDV_SAL_QUOT_ID = R.INDV_SAL_QUOT_ID
                                      LEFT JOIN DWH_REC_CUST_CONTRACT DC ON DC.CUST_CONTRACT_ID = C.CUST_CONTRACT_ID
                                     WHERE NVL(C.CONTRACT_END, 'NO') <> 'YES'
                                       AND NVL(C.COMPLETE_STATUS, 'NOT_COMPLETED') <> 'CANCELED'
                                       AND C.CUSTOMER_ID = L_CUSTOMER_ID),

                     DATES AS (SELECT B.*
                                     ,TO_CHAR(B.CUST_CONTRACT_DATE, 'DD/MM/YYYY') AS CONTR_CONTRACT_DATE
                                     ,TO_CHAR(B.CUST_CONTRACT_DATE, 'DD/MM/YYYY') AS CONTR_DATE_FROM
                                     ,TO_CHAR(CASE
                                                 WHEN B.CUST_CONTRACT_DATE IS NOT NULL AND B.EXPIRE_DATE IS NULL THEN
                                                  INDIVIDUAL_SAL_CONTRACT_PKG.GET_CONTRACT_END_DATE(B.CUST_CONTRACT_ID)
                                                 ELSE
                                                  B.EXPIRE_DATE
                                              END,
                                              'DD/MM/YYYY') AS CONTR_DATE_TO

                                 FROM BASE B),

                     METRICS AS (SELECT D.*
                                       ,INDV_SAL_QUOTATION_PKG.GET_QUOT_DAYS(D.PACKAGE_ID) AS TOTAL_DAYS
                                       ,NVL(INDIVIDUAL_SAL_CONTRACT_PKG.GET_REAL_REMAIN_DAYS(D.CUST_CONTRACT_ID), 0) AS REMAIN_DAYS
                                   FROM DATES D),

                     CALC AS (SELECT M.*
                                    ,ROUND(((M.TOTAL_DAYS - M.REMAIN_DAYS) / NULLIF(M.TOTAL_DAYS, 0)) * 100) || '%' AS CONTR_PROGRESS_PCT
                                    ,M.TOTAL_DAYS || '/' ||
                                     TO_CHAR(ROUND(GREATEST(0, M.TOTAL_DAYS - M.REMAIN_DAYS), 2), 'FM9999999990.00') AS CONTR_PROGRESS_TEXT
                                    ,ROUND(GREATEST(0, M.TOTAL_DAYS - M.REMAIN_DAYS), 2) AS CONTR_DAYS_CONSUMED
                                FROM METRICS M),

                     SERVICE_NAME AS (SELECT C.*
                                      --                                             ,

                                      --                                             CASE
                                      --                                                 WHEN C.PACKAGE_ID = 601001 THEN
                                      --                                                  CASE
                                      --                                                     WHEN L_LANG = C_DEFAULT_LANG THEN
                                      --                                                      TRANSLATE_TEXT(SM_SETTING_PKG.GET_DATA_LANG_ID,
                                      --                                                                     'Specified Housemaid Package') || ' ' || C.TOTAL_DAYS || ' ' ||
                                      --                                                      TRANSLATE_TEXT(SM_SETTING_PKG.GET_DATA_LANG_ID, 'Day')
                                      --
                                      --                                                     ELSE
                                      --                                                      'Specified Housemaid Package ' || C.TOTAL_DAYS || ' Day'
                                      --                                                  END
                                      --
                                      --                                                 WHEN C.PACKAGE_ID = 1281001 THEN
                                      --                                                  CASE
                                      --                                                     WHEN L_LANG = C_DEFAULT_LANG THEN
                                      --
                                      --                                                      TRANSLATE_TEXT(SM_SETTING_PKG.GET_DATA_LANG_ID, 'REC. HOUSEMAID') || ' ' ||
                                      --                                                      C.TOTAL_DAYS || ' ' ||
                                      --                                                      TRANSLATE_TEXT(SM_SETTING_PKG.GET_DATA_LANG_ID, 'Day')
                                      --                                                     ELSE
                                      --                                                      'REC. HOUSEMAID ' || C.TOTAL_DAYS || ' Day'
                                      --
                                      --                                                  END
                                      --
                                      --                                                 ELSE
                                      --                                                  CASE
                                      --                                                     WHEN L_LANG = C_DEFAULT_LANG THEN
                                      --
                                      --                                                      TRANSLATE_TEXT(SM_SETTING_PKG.GET_DATA_LANG_ID,
                                      --                                                                     'Resident Housemaid Package') || ' ' || C.TOTAL_DAYS || ' ' ||
                                      --                                                      TRANSLATE_TEXT(SM_SETTING_PKG.GET_DATA_LANG_ID, 'Day')
                                      --                                                     ELSE
                                      --                                                      'Resident Housemaid Package ' || C.TOTAL_DAYS || ' Day'
                                      --
                                      --                                                  END
                                      --                                              END

                                      --                                              AS CONTR_SERVICE_NAME
                                        FROM CALC C),

                     STATUS_FLAGS AS (SELECT S.*
                                            ,

                                             /* TEXT FROM LOOKUP (LANG-AWARE) */NVL(CASE
                                                    WHEN L_LANG = C_DEFAULT_LANG THEN
                                                     LKP.LOOKUP_NAME_L1
                                                    ELSE
                                                     LKP.LOOKUP_NAME_L2
                                                 END,
                                                 S.CONTRACT_STATUS) AS CONTR_STATUS_TEXT
                                            ,

                                             /* RAW STATUS (NO MAPPING) */S.CONTRACT_STATUS AS CONTR_STATUS_CODE
                                            ,

                                             /* KEEP FILTER LOGIC (unchanged behavior) */CASE
                                                WHEN S.CONTRACT_STATUS = 'ACTIVE' THEN
                                                 'Active'
                                                ELSE
                                                 S.CONTRACT_STATUS
                                             END AS CONTR_STATUS_FILTER

                                        FROM SERVICE_NAME S

                                        LEFT JOIN SM_LOOKUP LKP ON LKP.LOOKUP_TYPE = 'INDV_CONTRACT_STATUS'
                                                               AND LKP.LOOKUP_VALUE = S.CONTRACT_STATUS
                                                               AND NVL(LKP.ACTIVE, 0) = 1),

                     PAYMENT AS (SELECT SF.*
                                       ,CASE
                                           WHEN SF.CONTRACT_STATUS = 'PENDING' AND
                                                (NVL(JSON_VALUE(INDIVIDUAL_SAL_CONTRACT_PKG.IS_CONTRACT_VALID_TO_DELIVER_LABOR(SF.CUST_CONTRACT_ID,
                                                                                                                               NULL,
                                                                                                                               'JSON'),
                                                                '$.REMAIN_DEPOSIT' RETURNING NUMBER),
                                                     0) <> 0 OR NVL(JSON_VALUE(INDIVIDUAL_SAL_CONTRACT_PKG.IS_CONTRACT_VALID_TO_DELIVER_LABOR(SF.CUST_CONTRACT_ID,
                                                                                                                                               NULL,
                                                                                                                                               'JSON'),
                                                                                '$.REMAIN_INS' RETURNING NUMBER),
                                                                     0) <> 0) THEN
                                            1
                                           ELSE
                                            0
                                        END AS PAYMENT_AWAITED
                                   FROM STATUS_FLAGS SF)
                        SELECT P.CUST_CONTRACT_ID
                              ,P.CUST_CONTRACT_SYMBOL AS CONTR_CONTRACT_NO
                              ,P.CONTR_CONTRACT_DATE
                              ,P.CONTR_DATE_FROM
                              ,P.CONTR_DATE_TO
                              ,P.CONTR_PROGRESS_PCT
                              ,P.CONTR_PROGRESS_TEXT
                              ,P.CONTR_DAYS_CONSUMED
                               --                               ,P.CONTR_SERVICE_NAME
                              ,P.PACKAGE_NAME
                              ,SM_COUNTRY_PKG.GET_COUNTRY_NAME(P.NATIONALITY_ID) AS CONTR_NATIONALITY
                              ,NVL(P.QUOT_DAYS, P.TOTAL_DAYS) || CASE
                                  WHEN P.PACKAGE_TYPE = 'HOURLY' THEN
                                   CASE
                                      WHEN L_LANG = C_DEFAULT_LANG THEN
                                       ' ' || TRANSLATE_TEXT(SM_SETTING_PKG.GET_DATA_LANG_ID, 'visits')
                                      ELSE
                                       ' visits'
                                   END
                                  ELSE
                                   CASE
                                      WHEN L_LANG = C_DEFAULT_LANG THEN
                                       ' ' || TRANSLATE_TEXT(SM_SETTING_PKG.GET_DATA_LANG_ID, 'days')
                                      ELSE
                                       ' days'
                                   END
                               END AS CONTR_CONTRACT_PERIOD
                              ,P.CONTRACT_STATUS
                              ,P.PAYMENT_AWAITED
                              ,P.CONTR_STATUS_TEXT
                              ,P.CONTR_STATUS_CODE
                              ,P.CONTR_STATUS_FILTER
                              ,P.PACKAGE_ID
                              ,P.PACKAGE_TYPE
                              ,P.INDV_RFQ_ID
                              ,P.RFQ_SYMBOL
                              ,ROW_NUMBER() OVER (ORDER BY P.CUST_CONTRACT_ID DESC) RN
                          FROM PAYMENT P
                         WHERE (L_CONTRACT_STATUS_FILTER IS NULL OR P.CONTR_STATUS_FILTER = L_CONTRACT_STATUS_FILTER OR
                               P.CONTR_STATUS_CODE = L_CONTRACT_STATUS_FILTER))
                         WHERE RN > L_OFFSET
                           AND RN <= L_OFFSET + L_PAGE_SIZE
              )

      ;

      ------------------------------------------------------------------
      -- Ensure JSON array when no rows
      ------------------------------------------------------------------
      IF L_DATA IS NULL THEN
         L_DATA := '[]';
      END IF;

      ------------------------------------------------------------------

      -- Success response
      ------------------------------------------------------------------
      ABSH_API_UTIL_PKG.SUCCESS_RESPONSE(P_DATA => L_DATA, P_LANG => L_LANG);

      RETURN 200;

   EXCEPTION
      WHEN OTHERS THEN

         ABSH_API_UTIL_PKG.LOG_ERROR(SQLERRM,
                                     SQLCODE,
                                     DBMS_UTILITY.FORMAT_ERROR_BACKTRACE,
                                     'GET_CUSTOMER_CONTRACTS',
                                     'rec_cust_contract');

         ABSH_API_UTIL_PKG.ERROR_RESPONSE(500, 'ERR_INTERNAL', L_LANG);

         RETURN 500;

   END GET_CUSTOMER_CONTRACTS;
   ----------------------------------------------------------------------------------------------------------------------

   FUNCTION GET_INVOICES(P_PAYLOAD_JSON IN CLOB) RETURN NUMBER IS

      ------------------------------------------------------------------
      -- Variables
      ------------------------------------------------------------------
      L_USER_ID     NUMBER;
      L_CUST_ID     NUMBER;
      L_CUST_TYPE   VARCHAR2(200);
      L_CUSTOMER_ID NUMBER;
      L_POT_CUST_ID NUMBER;
      L_LANG        VARCHAR2(10);
      L_DATA        CLOB;
      L_TOKEN       VARCHAR2(4000);

      L_PAGE NUMBER := NVL(JSON_VALUE(P_PAYLOAD_JSON, '$.page' RETURNING NUMBER), 1);
      L_PAGE_SIZE CONSTANT NUMBER := 30;
      L_OFFSET NUMBER;

   BEGIN

      ------------------------------------------------------------------
      -- Validate request body
      ------------------------------------------------------------------
      IF P_PAYLOAD_JSON IS NULL OR LENGTH(TRIM(P_PAYLOAD_JSON)) = 0 THEN
         ABSH_API_UTIL_PKG.ERROR_RESPONSE(400, 'ERR_MISSING_PARAM', C_DEFAULT_LANG, APEX_T_VARCHAR2('NAME', 'body'));
         RETURN 400;
      END IF;

      ------------------------------------------------------------------
      -- Resolve language
      ------------------------------------------------------------------
      L_LANG := NVL(ABSH_API_UTIL_PKG.RESOLVE_LANG(JSON_VALUE(P_PAYLOAD_JSON, '$.acceptLanguage')), C_DEFAULT_LANG);

      ------------------------------------------------------------------
      -- Pagination setup
      ------------------------------------------------------------------
      IF L_PAGE < 1 THEN
         L_PAGE := 1;
      END IF;

      L_OFFSET := (L_PAGE - 1) * L_PAGE_SIZE;

      ------------------------------------------------------------------
      -- Extract Bearer Token
      ------------------------------------------------------------------
      L_TOKEN := ABSH_API_UTIL_PKG.GET_BEARER_TOKEN;

      IF L_TOKEN IS NULL OR LENGTH(TRIM(L_TOKEN)) = 0 THEN
         ABSH_API_UTIL_PKG.ERROR_RESPONSE(400, 'ERR_MISSING_PARAM', L_LANG, APEX_T_VARCHAR2('NAME', 'Authorization'));
         RETURN 400;
      END IF;

      ------------------------------------------------------------------
      -- Validate JWT
      ------------------------------------------------------------------
      L_USER_ID := ABSH_API_PRIVATE_PKG.VALIDATE_JWT_AND_GET_USER_ID(L_TOKEN);

      IF L_USER_ID IS NULL THEN
         ABSH_API_UTIL_PKG.ERROR_RESPONSE(401, 'ERR_UNAUTHORIZED', L_LANG);
         RETURN 401;
      END IF;

      ------------------------------------------------------------------
      -- Get Customer / Potential Customer
      ------------------------------------------------------------------
      ABSH_API_UTIL_PKG.GET_CUSTOMER_INFO(L_USER_ID, L_CUST_ID, L_CUST_TYPE);

      IF L_CUST_TYPE = 'CUSTOMER' THEN
         L_CUSTOMER_ID := L_CUST_ID;
      ELSIF L_CUST_TYPE = 'POTENTIAL' THEN
         L_POT_CUST_ID := L_CUST_ID;
      END IF;

      IF L_CUSTOMER_ID IS NULL AND L_POT_CUST_ID IS NULL THEN
         ABSH_API_UTIL_PKG.ERROR_RESPONSE(403,
                                          'ERR_USER_NOT_FOUND Please provide either potentialCustomerId or appCustomerId',
                                          L_LANG);
         RETURN 403;
      END IF;

      ------------------------------------------------------------------
      -- Build paginated invoices JSON
      ------------------------------------------------------------------
      SELECT CASE
                WHEN COUNT(*) = 0 THEN
                 TO_CLOB('[]')
                ELSE
                 JSON_ARRAYAGG(JSON_OBJECT('invoice_symbol' VALUE INVOICE_SYMBOL,
                                           'invoice_type' VALUE INVOICE_TYPE,
                                           'invoice_date' VALUE INVOICE_DATE,
                                           'invoice_amount' VALUE INVOICE_AMOUNT,
                                           'working_days' VALUE WORKING_DAYS,
                                           'status_label' VALUE STATUS_LABEL NULL ON NULL RETURNING CLOB) ORDER BY
                               TO_DATE(NVL(INVOICE_DATE, '01/01/1900'), 'DD/MM/YYYY') DESC RETURNING CLOB)
             END
        INTO L_DATA
        FROM (SELECT *


                FROM (SELECT AR.INVOICE_SYMBOL
                            ,

                             CASE AR.INVOICE_TYPE

                                WHEN 'INDV_STANDARD' THEN

                                 'Standard'
                                WHEN 'INDV_DEBIT_MEMO' THEN
                                 'DebitMemo'
                                WHEN 'INDV_DEPOSIT' THEN
                                 'Deposit'
                                WHEN 'STANDARD' THEN
                                 'Standard'
                                WHEN 'INDV_CREDIT_MEMO' THEN
                                 'CreditMemo'
                                WHEN 'CREDIT_MEMO' THEN
                                 'CreditMemo'
                                WHEN 'DEBIT_MEMO' THEN
                                 'DebitMemo'
                                WHEN 'INDV_DELAYED_MONTH' THEN
                                 'DelayedMonth'
                                WHEN 'INDV_STD_MEDIATE' THEN
                                 'StandardMediate'
                                WHEN 'INDV_DEPOSIT_MEDIATE' THEN
                                 'DepositMediate'
                                ELSE
                                 AR.INVOICE_TYPE
                             END AS INVOICE_TYPE
                            ,

                             TO_CHAR(AR.INVOICE_DATE, 'DD/MM/YYYY') AS INVOICE_DATE
                            ,

                             CASE
                                WHEN AR.INVOICE_TYPE = 'INDV_DEBIT_MEMO' THEN
                                 AR.MEMO_AMOUNT
                                ELSE
                                 AR.NET_AMOUNT + AR.TAX_AMOUNT
                             END AS INVOICE_AMOUNT
                            ,

                             NVL(EMP.WORKING_DAYS, 0) AS WORKING_DAYS
                            ,

                             CASE
                                WHEN NVL(PAY.PAID_AMOUNT, 0) < CASE
                                        WHEN AR.INVOICE_TYPE = 'INDV_DEBIT_MEMO' THEN
                                         AR.MEMO_AMOUNT
                                        ELSE
                                         AR.NET_AMOUNT + AR.TAX_AMOUNT
                                     END THEN
                                 'Unpaid'
                                ELSE
                                 'Paid'
                             END AS STATUS_LABEL
                            ,

                             ROW_NUMBER() OVER (ORDER BY AR.TO_DESERVE_DATE DESC) RN

                        FROM AR_INVOICE AR

                        JOIN REC_CUST_CONTRACT C ON AR.CUST_CONTRACT_ID = C.CUST_CONTRACT_ID

                        JOIN AR_INV_SCHED_PAYMENT INVP ON AR.INVOICE_ID = INVP.INVOICE_ID

                        LEFT JOIN (SELECT AID.INVOICE_ID, SUM(NVL(ADE.WORKING_DAYS, 0)) AS WORKING_DAYS
                                    FROM AR_INVOICE_DTL AID
                                    JOIN AR_INVOICE_DTL_EMP ADE ON AID.AR_INVOICE_DTL_ID = ADE.AR_INVOICE_DTL_ID
                                   GROUP BY AID.INVOICE_ID) EMP ON EMP.INVOICE_ID = AR.INVOICE_ID

                        LEFT JOIN (SELECT ARL.SCHED_PAYMENT_ID, SUM(ARL.LINE_RECEIPT_AMOUNT) AS PAID_AMOUNT
                                    FROM AR_RECEIPT_LINE ARL
                                    JOIN AR_RECEIPT_BUSINESS_PARTNER ARBP ON ARBP.RECEIPT_BUSINESS_PARTNER_ID =
                                                                             ARL.RECEIPT_BUSINESS_PARTNER_ID
                                    JOIN AR_RECEIPT AR ON AR.RECEIPT_ID = ARBP.RECEIPT_ID
                                   WHERE ARL.DELETED_FLAG = DATE '0001-01-01'
                                     AND AR.CONFIRMED = 1
                                   GROUP BY ARL.SCHED_PAYMENT_ID) PAY ON PAY.SCHED_PAYMENT_ID = INVP.SCHED_PAYMENT_ID

                       WHERE AR.INVOICE_TYPE IN ('INDV_STANDARD', 'INDV_DEBIT_MEMO', 'INDV_DEPOSIT')
                         AND AR.CUSTOMER_ID = L_CUSTOMER_ID)
               WHERE RN > L_OFFSET
                 AND RN <= L_OFFSET + L_PAGE_SIZE);

      ------------------------------------------------------------------
      -- Success response
      ------------------------------------------------------------------
      ABSH_API_UTIL_PKG.SUCCESS_RESPONSE(P_DATA => L_DATA, P_LANG => L_LANG);

      RETURN 200;

   EXCEPTION
      WHEN OTHERS THEN
         ABSH_API_UTIL_PKG.LOG_ERROR(SQLERRM,
                                     SQLCODE,
                                     DBMS_UTILITY.FORMAT_ERROR_BACKTRACE,
                                     'GET_INVOICES',
                                     'AR_INVOICE / REC_CUST_CONTRACT / AR_INV_SCHED_PAYMENT');

         ABSH_API_UTIL_PKG.ERROR_RESPONSE(500, 'ERR_INTERNAL', L_LANG);

         RETURN 500;

   END GET_INVOICES;

   ----------------------------------------------------------------------------------------------------------------------

   FUNCTION GET_RECEIPTS(P_PAYLOAD_JSON IN CLOB) RETURN NUMBER IS

      ------------------------------------------------------------------
      -- Variables
      ------------------------------------------------------------------
      L_USER_ID     NUMBER;
      L_CUST_ID     NUMBER;
      L_CUST_TYPE   VARCHAR2(200);
      L_CUSTOMER_ID NUMBER;
      L_POT_CUST_ID NUMBER;
      L_LANG        VARCHAR2(10);
      L_DATA        CLOB;
      L_TOKEN       VARCHAR2(4000);

      L_PAGE NUMBER := NVL(JSON_VALUE(P_PAYLOAD_JSON, '$.page' RETURNING NUMBER), 1);
      L_PAGE_SIZE CONSTANT NUMBER := 30;
      L_OFFSET NUMBER;

   BEGIN

      ------------------------------------------------------------------
      -- Validate request body
      ------------------------------------------------------------------
      IF P_PAYLOAD_JSON IS NULL OR LENGTH(TRIM(P_PAYLOAD_JSON)) = 0 THEN
         ABSH_API_UTIL_PKG.ERROR_RESPONSE(400, 'ERR_MISSING_PARAM', C_DEFAULT_LANG, APEX_T_VARCHAR2('NAME', 'body'));
         RETURN 400;
      END IF;

      ------------------------------------------------------------------
      -- Resolve language
      ------------------------------------------------------------------
      L_LANG := NVL(ABSH_API_UTIL_PKG.RESOLVE_LANG(JSON_VALUE(P_PAYLOAD_JSON, '$.acceptLanguage')), C_DEFAULT_LANG);

      ------------------------------------------------------------------
      -- Pagination setup
      ------------------------------------------------------------------
      IF L_PAGE < 1 THEN
         L_PAGE := 1;
      END IF;

      L_OFFSET := (L_PAGE - 1) * L_PAGE_SIZE;

      ------------------------------------------------------------------
      -- Extract Bearer Token
      ------------------------------------------------------------------
      L_TOKEN := ABSH_API_UTIL_PKG.GET_BEARER_TOKEN;

      IF L_TOKEN IS NULL OR LENGTH(TRIM(L_TOKEN)) = 0 THEN
         ABSH_API_UTIL_PKG.ERROR_RESPONSE(400, 'ERR_MISSING_PARAM', L_LANG, APEX_T_VARCHAR2('NAME', 'Authorization'));
         RETURN 400;
      END IF;

      ------------------------------------------------------------------
      -- Validate JWT and resolve user
      ------------------------------------------------------------------
      L_USER_ID := ABSH_API_PRIVATE_PKG.VALIDATE_JWT_AND_GET_USER_ID(L_TOKEN);

      IF L_USER_ID IS NULL THEN
         ABSH_API_UTIL_PKG.ERROR_RESPONSE(401, 'ERR_UNAUTHORIZED', L_LANG);
         RETURN 401;
      END IF;

      ------------------------------------------------------------------
      -- Get Customer ID or Potential Customer ID
      ------------------------------------------------------------------
      ABSH_API_UTIL_PKG.GET_CUSTOMER_INFO(L_USER_ID, L_CUST_ID, L_CUST_TYPE);

      IF L_CUST_TYPE = 'CUSTOMER' THEN
         L_CUSTOMER_ID := L_CUST_ID;
      ELSIF L_CUST_TYPE = 'POTENTIAL' THEN
         L_POT_CUST_ID := L_CUST_ID;
      END IF;

      IF L_CUSTOMER_ID IS NULL AND L_POT_CUST_ID IS NULL THEN
         ABSH_API_UTIL_PKG.ERROR_RESPONSE(403,
                                          'ERR_USER_NOT_FOUND Please provide either potentialCustomerId or appCustomerId',
                                          L_LANG);
         RETURN 403;
      END IF;

      ------------------------------------------------------------------
      -- Build paginated Receipts JSON
      ------------------------------------------------------------------
      SELECT CASE
                WHEN COUNT(*) = 0 THEN
                 TO_CLOB('[]')
                ELSE
                 JSON_ARRAYAGG(JSON_OBJECT('receipt_number' VALUE RECEIPT_NUMBER,
                                           'trans_date' VALUE TO_CHAR(TRANS_DATE, 'DD/MM/YYYY'),
                                           'amount' VALUE AMOUNT_RAW,
                                           'description' VALUE DESCRIPTION,
                                           'trans_id' VALUE TRANS_ID,
                                           'trans_type' VALUE TRANS_TYPE,
                                           'payment_method' VALUE PAYMENT_METHOD,
                                           'bank' VALUE BANK,
                                           'bank_number' VALUE BANK_NUMBER,
                                           'contract_number' VALUE CONTRACT_NUMBER,
                                           'package_number' VALUE PACKAGE_NUMBER NULL ON NULL RETURNING CLOB) ORDER BY
                               TRANS_DATE DESC RETURNING CLOB)
             END
        INTO L_DATA
        FROM (SELECT *
                FROM (
                      ------------------------------------------------------------------
                      -- RECEIPTS + CREDIT MEMOS
                      ------------------------------------------------------------------
                      SELECT R.RECEIPT_SYMBOL AS RECEIPT_NUMBER
                             ,R.RECEIPT_DATE AS TRANS_DATE
                             ,NVL(R.TOT_AMOUNT, 0) AS AMOUNT_RAW
                             ,NVL(R.DESCRIPTION_L1, R.DESCRIPTION_L2) AS DESCRIPTION
                             ,R.RECEIPT_ID AS TRANS_ID
                             ,'RECEIPT' AS TRANS_TYPE
                             ,NVL(PAY.PAY_METHOD_NAME, R.DESCRIPTION_L2) AS PAYMENT_METHOD
                             ,PAY.BANK_NAME AS BANK
                             ,PAY.BANK_ACCOUNT_NUMBER AS BANK_NUMBER
                             ,C.CUST_CONTRACT_SYMBOL AS CONTRACT_NUMBER
                              --                              ,RFQ.INDV_SAL_QUOT_ID AS PACKAGE_NUMBER
                             ,CASE
                                 WHEN L_LANG = C_DEFAULT_LANG THEN
                                  ISQ.QUOT_NAME_L1
                                 ELSE
                                  ISQ.QUOT_NAME_L2
                              END AS PACKAGE_NUMBER
                        FROM AR_RECEIPT R
                        JOIN REC_CUST_CONTRACT C ON R.INDV_CUST_CONTRACT_ID = C.CUST_CONTRACT_ID
                        LEFT JOIN INDV_SAL_RFQ RFQ ON RFQ.INDV_RFQ_ID = C.INDV_RFQ_ID
                        LEFT JOIN INDV_SAL_QUOTATION ISQ ON ISQ.INDV_SAL_QUOT_ID = RFQ.INDV_SAL_QUOT_ID

                        LEFT JOIN (SELECT PM.PAY_METHOD_BANK_ID
                                         ,PAY_METHOD.PAY_METHOD_SYMBOL || ' ' || CASE
                                             WHEN LOWER(L_LANG) = C_DEFAULT_LANG THEN
                                              NVL(PAY_METHOD.PAY_METHOD_NAME_L1, PAY_METHOD.PAY_METHOD_NAME_L2)
                                             ELSE
                                              NVL(PAY_METHOD.PAY_METHOD_NAME_L2, PAY_METHOD.PAY_METHOD_NAME_L1)
                                          END AS PAY_METHOD_NAME
                                         ,BANK.BANK_ACCOUNT_NUMBER
                                         ,BANK.BANK_NAME
                                     FROM AR_PAY_METHOD_BANK PM
                                     JOIN AR_PAY_METHOD PAY_METHOD ON PM.PAY_METHOD_ID = PAY_METHOD.PAY_METHOD_ID
                                     LEFT JOIN (SELECT CBA.BANK_ACCOUNT_ID
                                                     ,CBA.BANK_ACCOUNT_NUMBER
                                                     ,CASE
                                                         WHEN LOWER(L_LANG) = C_DEFAULT_LANG THEN
                                                          NVL(CB.BANK_NAME_L1, CB.BANK_NAME_L2)
                                                         ELSE

                                                          NVL(CB.BANK_NAME_L2, CB.BANK_NAME_L1)
                                                      END AS BANK_NAME
                                                 FROM CASH_BANK_ACCOUNT CBA
                                                 JOIN CASH_BANK_BRANCH CBB ON CBB.BRANCH_ID = CBA.BANK_BRANCH_ID
                                                 JOIN CASH_BANK CB ON CB.BANK_ID = CBB.BANK_ID) BANK ON BANK.BANK_ACCOUNT_ID =
                                                                                                        PM.BANK_ACCOUNT_ID
                                    WHERE PAY_METHOD.SECTION_TYPE IN ('ALL', 'PERSON')) PAY ON PAY.PAY_METHOD_BANK_ID =
                                                                                               R.PAY_METHOD_BANK_ID
                       WHERE NVL(C.COMPLETE_STATUS, 'NOT_COMPLETED') <> 'CANCELED'
                         AND NVL(R.CONFIRMED, 0) = 1
                         AND C.CUSTOMER_ID = L_CUSTOMER_ID

                      UNION ALL

                      SELECT AR.INVOICE_SYMBOL AS RECEIPT_NUMBER
                             ,AR.INVOICE_DATE AS TRANS_DATE
                             ,NVL(AR.MEMO_AMOUNT, 0) AS AMOUNT_RAW
                             ,NVL(AR.INVOICE_DESC_L1, AR.INVOICE_DESC_L2) AS DESCRIPTION
                             ,AR.INVOICE_ID AS TRANS_ID
                             ,'CR_MEMO' AS TRANS_TYPE
                             ,'' AS PAYMENT_METHOD
                             ,'' AS BANK
                             ,'' AS BANK_NUMBER
                             ,C.CUST_CONTRACT_SYMBOL AS CONTRACT_NUMBER
                              --                              ,RFQ.INDV_SAL_QUOT_ID AS PACKAGE_NUMBER
                             ,CASE
                                 WHEN L_LANG = C_DEFAULT_LANG THEN
                                  ISQ.QUOT_NAME_L1
                                 ELSE
                                  ISQ.QUOT_NAME_L2
                              END AS PACKAGE_NUMBER

                        FROM AR_INVOICE AR
                        JOIN REC_CUST_CONTRACT C ON AR.CUST_CONTRACT_ID = C.CUST_CONTRACT_ID
                        LEFT JOIN INDV_SAL_RFQ RFQ ON RFQ.INDV_RFQ_ID = C.INDV_RFQ_ID
                        LEFT JOIN INDV_SAL_QUOTATION ISQ ON ISQ.INDV_SAL_QUOT_ID = RFQ.INDV_SAL_QUOT_ID

                       WHERE AR.INVOICE_TYPE = 'INDV_CREDIT_MEMO'
                         AND AR.CUSTOMER_ID = L_CUSTOMER_ID)
               WHERE ROWNUM <= L_OFFSET + L_PAGE_SIZE)
       WHERE ROWNUM > L_OFFSET;

      ------------------------------------------------------------------
      -- Success Response
      ------------------------------------------------------------------
      ABSH_API_UTIL_PKG.SUCCESS_RESPONSE(P_DATA => L_DATA, P_LANG => L_LANG);

      RETURN 200;

   EXCEPTION
      WHEN OTHERS THEN
         ABSH_API_UTIL_PKG.LOG_ERROR(SQLERRM,
                                     SQLCODE,
                                     DBMS_UTILITY.FORMAT_ERROR_BACKTRACE,
                                     'GET_RECEIPTS',
                                     'AR_RECEIPT / AR_INVOICE / REC_CUST_CONTRACT');

         ABSH_API_UTIL_PKG.ERROR_RESPONSE(500, 'ERR_INTERNAL', L_LANG);

         RETURN 500;

   END GET_RECEIPTS;
   ----------------------------------------------------------------------------------------------------------------------
   FUNCTION RENEW_CONTRACT(P_PAYLOAD_JSON IN CLOB) RETURN NUMBER IS
      L_LANG                  VARCHAR2(10);
      L_TERMS_AND_CONDITIONS  VARCHAR2(10);
      L_INDV_SAL_QUOT_ID      NUMBER;
      L_SALES_CODE            VARCHAR2(50);
      L_REFE_CUST_CONTRACT_ID NUMBER;
      L_EMP_ID                NUMBER;
      L_ORDER_ADDRESS_ID      NUMBER;

      L_TOKEN       VARCHAR2(1000);
      L_USER_ID     NUMBER;
      L_CUST_ID     NUMBER;
      L_CUST_TYPE   VARCHAR2(20);
      L_CUSTOMER_ID NUMBER;
      L_POT_CUST_ID NUMBER;

      V_CONTRACT_SYMBOL     VARCHAR2(200);
      V_ADDRESS_ID          NUMBER;
      V_POT_NAME            VARCHAR2(500);
      V_CUSTOMER_FIRST_NAME VARCHAR2(500);
      V_CUSTOMER_LAST_NAME  VARCHAR2(500);
      V_CUSTOMER_ID         NUMBER;

      L_CONTRACT_ID         NUMBER;
      V_SUCC_MSG            VARCHAR2(1000);
      V_ERR_MSG             VARCHAR2(1000);
      L_DATA                CLOB;
   BEGIN
      L_LANG                  := NVL(JSON_VALUE(P_PAYLOAD_JSON, '$.lang'), C_DEFAULT_LANG);
      L_TERMS_AND_CONDITIONS  := UPPER(TRIM(JSON_VALUE(P_PAYLOAD_JSON, '$.termsAndConditions')));
      L_INDV_SAL_QUOT_ID      := JSON_VALUE(P_PAYLOAD_JSON, '$.packageId' RETURNING NUMBER);
      L_SALES_CODE            := TRIM(JSON_VALUE(P_PAYLOAD_JSON, '$.salesCode'));
      L_REFE_CUST_CONTRACT_ID := JSON_VALUE(P_PAYLOAD_JSON, '$.refCustContractId' RETURNING NUMBER);
      L_EMP_ID                := JSON_VALUE(P_PAYLOAD_JSON, '$.employeeId' RETURNING NUMBER);
      L_ORDER_ADDRESS_ID      := JSON_VALUE(P_PAYLOAD_JSON, '$.orderAddressId' RETURNING NUMBER);

      L_TOKEN := ABSH_API_UTIL_PKG.GET_BEARER_TOKEN;
      if L_TOKEN IS NULL THEN
         ABSH_API_UTIL_PKG.ERROR_RESPONSE(400, 'ERR_MISSING_PARAM', L_LANG, APEX_T_VARCHAR2('NAME', 'token'));
         RETURN 400;
      END IF;

      IF L_TERMS_AND_CONDITIONS <> 'YES' THEN
         ABSH_API_UTIL_PKG.ERROR_RESPONSE(400, 'ERR_MISSING_PARAM', L_LANG, APEX_T_VARCHAR2('NAME', 'termsAndConditions'));
         RETURN 400;
      END IF;

      IF L_INDV_SAL_QUOT_ID IS NULL THEN
         ABSH_API_UTIL_PKG.ERROR_RESPONSE(400, 'ERR_MISSING_PARAM', L_LANG, APEX_T_VARCHAR2('NAME', 'packageId'));
         RETURN 400;
      END IF;

      ABSH_API_UTIL_PKG.VALIDATE_API_KEY(ABSH_API_UTIL_PKG.GET_APIKEY);

      -- JWT Validate
      L_USER_ID := ABSH_API_PRIVATE_PKG.VALIDATE_JWT_AND_GET_USER_ID(L_TOKEN);

      -- Resolve Customer Info
      ABSH_API_UTIL_PKG.GET_CUSTOMER_INFO(L_USER_ID, L_CUST_ID, L_CUST_TYPE);
      IF L_CUST_TYPE = 'CUSTOMER' THEN
         L_CUSTOMER_ID := L_CUST_ID;
      ELSE
         L_POT_CUST_ID := L_CUST_ID;
      END IF;

      IF L_CUSTOMER_ID IS NULL AND L_POT_CUST_ID IS NULL THEN
         ABSH_API_UTIL_PKG.ERROR_RESPONSE(403, 'ERR_USER_NOT_FOUND Please provide either potentialCustomerId or appCustomerId', L_LANG);
         RETURN 403;
      END IF;

      IF ABSH_API_UTIL_PKG.IS_PROFILE_COMPLETE(L_USER_ID) = 0 THEN
         ABSH_API_UTIL_PKG.ERROR_RESPONSE(409, 'ERR_PROFILE_NOT_COMPLETE', L_LANG);
         RETURN 409;
      END IF;

      -- Potential Customer Address resolution (Logic migrated to Business Layer)
      IF L_CUSTOMER_ID IS NULL THEN
         ABSH_BUSINESS_PRIVATE_PKG.RESOLVE_POTENTIAL_CUSTOMER_ADDRESS(L_POT_CUST_ID, V_ADDRESS_ID, V_POT_NAME);
         V_CUSTOMER_LAST_NAME := V_POT_NAME;
      ELSE
         V_ADDRESS_ID := L_ORDER_ADDRESS_ID;
      END IF;

      IF V_CUSTOMER_LAST_NAME IS NULL THEN
         V_CUSTOMER_LAST_NAME := V_CUSTOMER_FIRST_NAME;
      END IF;

      -- Execute business logic procedure
      /*
       * WARNING/NOTE: Calling INDV_CONFIRM_ONLINE_REQUEST as a procedure with OUT parameters
       * for error messages and success text is discouraged according to our architecture standards:
       * 1. The business layer should communicate failures by raising standard database exceptions,
       *    rather than returning message strings in OUT parameters which requires manual checking.
       * 2. The API layer should not be parsing user-facing success strings (via REGEXP_SUBSTR)
       *    to extract entity IDs (like contract symbol). Instead, the business layer should return
       *    clean, typed scalar values or structures.
       */
      BEGIN
         INDV_SAL_REQUEST_PKG.INDV_CONFIRM_ONLINE_REQUEST(
             P_TERMS_AND_CONDITIONS    => L_TERMS_AND_CONDITIONS,
             P_INDV_SAL_QUOT_ID        => L_INDV_SAL_QUOT_ID,
             P_SESSION_POT_CUST_ID     => L_POT_CUST_ID,
             P_SESSION_APP_CUSTOMER_ID => L_CUSTOMER_ID,
             P_SESSION_USER_ID         => L_USER_ID,
             P_CUSTOMER_FIRST_NAME     => V_CUSTOMER_FIRST_NAME,
             P_CUSTOMER_LAST_NAME      => V_CUSTOMER_LAST_NAME,
             P_CUSTOMER_ADDRESS        => NVL(V_ADDRESS_ID, L_ORDER_ADDRESS_ID),
             P_CUSTOMER_IDENT_ID       => NULL,
             P_WORK_SKILL              => NULL,
             P_WORKED_BEFORE           => NULL,
             P_SALES_CODE              => L_SALES_CODE,
             P_EMP_ID                  => L_EMP_ID,
             P_REFE_CUST_CONTRACT_ID   => L_REFE_CUST_CONTRACT_ID,
             P_SHOWROOM                => NULL,
             P_ERR_MSG                 => V_ERR_MSG,
             P_SUCC_MSG                => V_SUCC_MSG,
             P_CUSTOMER_ID             => V_CUSTOMER_ID
         );

         IF V_ERR_MSG IS NOT NULL THEN
            ABSH_API_UTIL_PKG.ERROR_RESPONSE(400, V_ERR_MSG, L_LANG, APEX_T_VARCHAR2('MESSAGE', V_ERR_MSG));
            RETURN 400;
         END IF;

         -- Extract the contract symbol from the success message using RegEx
         V_CONTRACT_SYMBOL := REGEXP_SUBSTR(V_SUCC_MSG, 'Number\s+(\S+)', 1, 1, NULL, 1);

         IF V_SUCC_MSG IS NOT NULL THEN
            COMMIT;
         END IF;

      EXCEPTION
         WHEN OTHERS THEN
            ROLLBACK;
            ABSH_API_UTIL_PKG.ERROR_RESPONSE(500,
                                             'ERR_CONFIRMATION_FAILED',
                                             L_LANG,
                                             APEX_T_VARCHAR2('ERROR', SQLERRM || ' - ' || DBMS_UTILITY.FORMAT_ERROR_BACKTRACE));
            RETURN 500;
      END;

      -- Build JSON Response (auto-committed by ORDS)
      SELECT JSON_OBJECT('packageId' VALUE L_INDV_SAL_QUOT_ID,
                         'customerId' VALUE NVL(V_CUSTOMER_ID, L_CUSTOMER_ID),
                         'potentialCustomerId' VALUE L_POT_CUST_ID,
                         'appCustomerId' VALUE L_CUSTOMER_ID,
                         'message' VALUE V_SUCC_MSG,
                         'contractSymbol' VALUE V_CONTRACT_SYMBOL,
                         'addressId' VALUE V_ADDRESS_ID NULL ON NULL RETURNING CLOB)
        INTO L_DATA
        FROM DUAL;

      ABSH_API_UTIL_PKG.SUCCESS_RESPONSE(P_MESSAGE_KEY => 'REQUEST_CONFIRMED', P_LANG => L_LANG, P_DATA => L_DATA);
      RETURN 200;

   EXCEPTION
      WHEN OTHERS THEN
         ROLLBACK;
         ABSH_API_UTIL_PKG.ERROR_RESPONSE(500,
                                          'ERR_INTERNAL_ERROR',
                                          L_LANG,
                                          APEX_T_VARCHAR2('ERROR', SQLERRM || ' - ' || DBMS_UTILITY.FORMAT_ERROR_BACKTRACE));
         RETURN 500;
   END RENEW_CONTRACT;
   -----------------------------------------------------------------------------------
   FUNCTION RATE_WORKERS_API(P_PAYLOAD_JSON IN CLOB) RETURN NUMBER IS
      L_LANG         VARCHAR2(10);
      L_VISIT_ID     NUMBER;
      L_ORDER_ID     VARCHAR2(99);
      L_WORKERS_JSON CLOB;
      L_TOKEN        VARCHAR2(4000);
      L_USER_ID      NUMBER;
      L_DATA         CLOB;
      L_CUSTOMER_ID  NUMBER;
      L_CUST_TYPE    VARCHAR2(99);
   BEGIN
      ---------------------------------------------------------------
      -- 1. BASIC VALIDATIONS
      ---------------------------------------------------------------
      ABSH_API_UTIL_PKG.VALIDATE_API_KEY(ABSH_API_UTIL_PKG.GET_APIKEY);

      IF P_PAYLOAD_JSON IS NULL OR LENGTH(TRIM(P_PAYLOAD_JSON)) = 0 THEN
         ABSH_API_UTIL_PKG.ERROR_RESPONSE(400, 'ERR_MISSING_PARAM', C_DEFAULT_LANG, APEX_T_VARCHAR2('NAME', 'body'));
         RETURN 400;
      END IF;

      L_LANG := NVL(ABSH_API_UTIL_PKG.RESOLVE_LANG(JSON_VALUE(P_PAYLOAD_JSON, '$.acceptLanguage')), C_DEFAULT_LANG);

      L_VISIT_ID := JSON_VALUE(P_PAYLOAD_JSON, '$.visitId' RETURNING NUMBER);
      L_ORDER_ID := JSON_VALUE(P_PAYLOAD_JSON, '$.orderId');

      -- Extract workers array
      SELECT WORKERS_JSON
        INTO L_WORKERS_JSON
        FROM JSON_TABLE(P_PAYLOAD_JSON, '$' COLUMNS(WORKERS_JSON CLOB FORMAT JSON PATH '$.workers'));

      IF L_WORKERS_JSON IS NULL THEN
         ABSH_API_UTIL_PKG.ERROR_RESPONSE(400, 'ERR_MISSING_PARAM', L_LANG, APEX_T_VARCHAR2('NAME', 'workers'));
         RETURN 400;
      END IF;

      L_TOKEN   := ABSH_API_UTIL_PKG.GET_BEARER_TOKEN;
      L_USER_ID := ABSH_API_PRIVATE_PKG.VALIDATE_JWT_AND_GET_USER_ID(L_TOKEN);

      ABSH_API_UTIL_PKG.GET_CUSTOMER_INFO(L_USER_ID, L_CUSTOMER_ID, L_CUST_TYPE);

      ---------------------------------------------------------------
      -- 2. SECURITY & BUSINESS VALIDATIONS
      ---------------------------------------------------------------
      IF L_VISIT_ID IS NULL AND L_ORDER_ID IS NULL THEN
         ABSH_API_UTIL_PKG.ERROR_RESPONSE(400, 'ERR_MISSING_PARAM', L_LANG, APEX_T_VARCHAR2('NAME', 'orderId'));
         RETURN 400;
      END IF;

      -- A. If Visit context provided (Hourly)
      IF L_VISIT_ID IS NOT NULL THEN
         ABSH_RATING_PKG.VALIDATE_VISIT_CUSTOMER(P_VISIT_ID => L_VISIT_ID, P_CUSTOMER_ID => L_CUSTOMER_ID);

         -- Resolve Order ID if missing
         IF L_ORDER_ID IS NULL THEN
            SELECT ISR.RFQ_SYMBOL
              INTO L_ORDER_ID
              FROM INDV_SAL_RFQ ISR
              JOIN ABSH_VISIT_SCHEDULE VS ON VS.INDV_RFQ_ID = ISR.INDV_RFQ_ID
             WHERE VS.SCHEDULE_ID = L_VISIT_ID;

         END IF;
      END IF;

      -- B. If Order context provided (Live-in or Hourly)
      IF L_ORDER_ID IS NOT NULL THEN
         ABSH_RATING_PKG.VALIDATE_ORDER_CUSTOMER(P_ORDER_ID => L_ORDER_ID, P_CUSTOMER_ID => L_CUSTOMER_ID);
         ABSH_RATING_PKG.VALIDATE_ORDER_RATABLE(P_ORDER_ID => L_ORDER_ID);
      ELSE
         ABSH_API_UTIL_PKG.ERROR_RESPONSE(400, 'ERR_ORDER_ID_REQUIRED', L_LANG);
         RETURN 400;
      END IF;

      ---------------------------------------------------------------
      -- 3. EXECUTE CORE LOGIC
      ---------------------------------------------------------------
      ABSH_RATING_PKG.RATE_WORKERS(P_VISIT_ID     => L_VISIT_ID,
                                   P_ORDER_ID     => L_ORDER_ID,
                                   P_WORKERS_JSON => L_WORKERS_JSON,
                                   P_CREATED_BY   => TO_CHAR(L_USER_ID));

      SELECT JSON_OBJECT('orderId' VALUE L_ORDER_ID RETURNING CLOB) INTO L_DATA FROM DUAL;

      ABSH_API_UTIL_PKG.SUCCESS_RESPONSE(P_STATUS_CODE => 200,

                                         P_MESSAGE_KEY => 'RATING_SAVED',
                                         P_LANG        => L_LANG,
                                         P_DATA        => L_DATA);

      RETURN 200;
   EXCEPTION
      WHEN OTHERS THEN
         ABSH_API_UTIL_PKG.LOG_ERROR(SQLERRM,
                                     SQLCODE,
                                     DBMS_UTILITY.FORMAT_ERROR_BACKTRACE,
                                     'RATE_WORKERS_API',
                                     'ABSH_WORKER_RATINGS');
         ABSH_API_UTIL_PKG.ERROR_RESPONSE(500, 'ERR_INTERNAL', L_LANG);
         RETURN 500;
   END RATE_WORKERS_API;
   -----------------------------------------------------------------------------------

   FUNCTION RATE_ORDER_API(P_PAYLOAD_JSON IN CLOB) RETURN NUMBER IS
      L_TOKEN       VARCHAR2(4000);
      L_LANG        VARCHAR2(10);
      L_USER_ID     NUMBER;
      L_ORDER_ID    VARCHAR2(99);
      L_RATING      NUMBER;
      L_COMMENT     VARCHAR2(1000);
      L_DATA        CLOB;
      L_CUSTOMER_ID NUMBER;
      L_CUST_TYPE   VARCHAR2(99);
   BEGIN
      ABSH_API_UTIL_PKG.VALIDATE_API_KEY(ABSH_API_UTIL_PKG.GET_APIKEY);

      IF P_PAYLOAD_JSON IS NULL OR LENGTH(TRIM(P_PAYLOAD_JSON)) = 0 THEN
         ABSH_API_UTIL_PKG.ERROR_RESPONSE(400, 'ERR_MISSING_PARAM', C_DEFAULT_LANG, APEX_T_VARCHAR2('NAME', 'body'));
         RETURN 400;
      END IF;

      L_LANG     := NVL(ABSH_API_UTIL_PKG.RESOLVE_LANG(JSON_VALUE(P_PAYLOAD_JSON, '$.acceptLanguage')), C_DEFAULT_LANG);
      L_ORDER_ID := JSON_VALUE(P_PAYLOAD_JSON, '$.orderId');
      L_RATING   := JSON_VALUE(P_PAYLOAD_JSON, '$.rating' RETURNING NUMBER);
      L_COMMENT  := JSON_VALUE(P_PAYLOAD_JSON, '$.comment');

      L_TOKEN := ABSH_API_UTIL_PKG.GET_BEARER_TOKEN;
      IF L_TOKEN IS NULL THEN
         ABSH_API_UTIL_PKG.ERROR_RESPONSE(401, 'ERR_UNAUTHORIZED', L_LANG);
         RETURN 401;
      END IF;

      IF L_ORDER_ID IS NULL THEN
         ABSH_API_UTIL_PKG.ERROR_RESPONSE(400, 'ERR_MISSING_PARAM', L_LANG, APEX_T_VARCHAR2('NAME', 'orderId'));
         RETURN 400;
      END IF;

      IF L_RATING IS NULL THEN

         ABSH_API_UTIL_PKG.ERROR_RESPONSE(400, 'ERR_MISSING_PARAM', L_LANG, APEX_T_VARCHAR2('NAME', 'rating'));
         RETURN 400;
      END IF;

      L_USER_ID := ABSH_API_PRIVATE_PKG.VALIDATE_JWT_AND_GET_USER_ID(L_TOKEN);
      ABSH_API_UTIL_PKG.GET_CUSTOMER_INFO(L_USER_ID, L_CUSTOMER_ID, L_CUST_TYPE);

      -- Security & Business Validations
      ABSH_RATING_PKG.VALIDATE_ORDER_CUSTOMER(P_ORDER_ID => L_ORDER_ID, P_CUSTOMER_ID => L_CUSTOMER_ID);

      ABSH_RATING_PKG.RATE_ORDER(P_ORDER_ID       => L_ORDER_ID,
                                 P_CUSTOMER_ID    => L_CUSTOMER_ID,
                                 P_OVERALL_RATING => L_RATING,
                                 P_COMMENT_TEXT   => L_COMMENT,
                                 P_CREATED_BY     => TO_CHAR(L_USER_ID));

      SELECT JSON_OBJECT('orderId' VALUE L_ORDER_ID RETURNING CLOB) INTO L_DATA FROM DUAL;

      ABSH_API_UTIL_PKG.SUCCESS_RESPONSE(P_STATUS_CODE => 200,
                                         P_MESSAGE_KEY => 'ORDER_RATED_SUCCESS',


                                         P_LANG        => L_LANG,
                                         P_DATA        => L_DATA);

      RETURN 200;
   EXCEPTION
      WHEN OTHERS THEN
         ABSH_API_UTIL_PKG.LOG_ERROR(SQLERRM,
                                     SQLCODE,
                                     DBMS_UTILITY.FORMAT_ERROR_BACKTRACE,
                                     'RATE_ORDER_API',
                                     'ABSH_ORDER_RATINGS');
         ABSH_API_UTIL_PKG.ERROR_RESPONSE(500, 'ERR_INTERNAL', L_LANG);
         RETURN 500;
   END RATE_ORDER_API;
   -----------------------------------------------------------------------------------
-----------------------------------------------------------------------------------
-----------------------------------------------------------------------------------
-------------------------------------------------------------------------------------------------------------------------------------------------

END ABSH_API_PRIVATE_PKG;





/
