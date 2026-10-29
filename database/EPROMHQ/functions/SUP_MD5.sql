
  CREATE OR REPLACE EDITIONABLE FUNCTION "EPROMHQ"."SUP_MD5"
 (p_txt in varchar2)
return varchar2
 as
   md5 raw(16); -- MD5 is 128 = 16 * 8 bits

begin

   md5 := dbms_crypto.hash(
            utl_i18n.string_to_raw(p_txt, 'AL32UTF8'),
            dbms_crypto.hash_md5
          );

return md5;

end;
/
