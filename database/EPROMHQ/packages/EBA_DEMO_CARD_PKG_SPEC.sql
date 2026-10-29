
  CREATE OR REPLACE EDITIONABLE PACKAGE "EPROMHQ"."EBA_DEMO_CARD_PKG" as
    function get_video_duration (
        p_video_id in varchar2 ) return varchar2;
    procedure get_profile_image (
        p_empno in number);
end eba_demo_card_pkg;
/
