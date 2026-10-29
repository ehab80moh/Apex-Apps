
  CREATE OR REPLACE EDITIONABLE TRIGGER "EPROMHQ"."TINYMCE_IMAGES_BIU"
    before insert or update
    on tinymce_images
    for each row
begin
    if inserting then
        :new.created := sysdate;
        :new.created_by := coalesce(sys_context('APEX$SESSION','APP_USER'),user);
    end if;
    :new.updated := sysdate;
    :new.updated_by := coalesce(sys_context('APEX$SESSION','APP_USER'),user);
end tinymce_images_biu;
/
ALTER TRIGGER "EPROMHQ"."TINYMCE_IMAGES_BIU" ENABLE;
