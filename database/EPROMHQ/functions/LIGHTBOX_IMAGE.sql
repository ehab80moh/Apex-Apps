
  CREATE OR REPLACE EDITIONABLE FUNCTION "EPROMHQ"."LIGHTBOX_IMAGE"
(
  p_image_url in varchar2
, p_box_title in varchar2
, p_link_text in varchar2
,p_image_group in varchar2 DEFAULT 'image'
) return varchar2 as
begin
  return '<a href="' ||P_IMAGE_URL ||'" data-lightbox="' ||p_image_group||'" data-title="' ||P_BOX_TITLE|| '">'||P_LINK_TEXT||'</a>';
end lightbox_image;
/
