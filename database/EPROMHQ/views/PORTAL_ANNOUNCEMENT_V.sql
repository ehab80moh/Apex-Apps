
  CREATE OR REPLACE FORCE EDITIONABLE VIEW "EPROMHQ"."PORTAL_ANNOUNCEMENT_V" ("ID", "TITEL_ANNOUNCEMENT", "URL", "BODY", "IMAGE_ID", "IMAGE_ANNOUNCEMENT", "EXPIRE_DATE", "CREATED_AT", "CREATED_BY") AS
  SELECT id,
         titel_announcement,
         url,
         body,
         image_id,
         image_announcement,
         expire_date,
         created_at,
         created_by
  FROM   epromhq.portal_announcement
  ORDER  BY created_at DESC;
