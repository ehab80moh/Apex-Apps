
  CREATE OR REPLACE EDITIONABLE PACKAGE "EPROMHQ"."SPORTS_DAY_PKG" authid definer as
  function normalize_games(p_games varchar2) return varchar2;
  function has_card_side(p_side number) return boolean;
  function card_complete return boolean;
  function card_html return clob;
  procedure download_card(p_side number);
  function saved_games return varchar2;
  function is_registered return boolean;
  function registration_html return clob;
  procedure cancel_registration;
  procedure upload_card(p_front_name varchar2, p_back_name varchar2);
  procedure register_games(p_games varchar2);
end sports_day_pkg;
/
