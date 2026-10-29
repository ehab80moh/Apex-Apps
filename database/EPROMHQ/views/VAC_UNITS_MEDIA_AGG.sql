
  CREATE OR REPLACE FORCE EDITIONABLE VIEW "EPROMHQ"."VAC_UNITS_MEDIA_AGG" ("UNIT_ID", "IMAGES", "THUMBS") AS
  SELECT unit_id, LISTAGG(m.media_link,',') images ,LISTAGG(replace(m.media_link,'attach/','attach/thumbs/'),',') thumbs
FROM vac_units_media m WHERE  m.media_type='IMAGE'
group by unit_id;
