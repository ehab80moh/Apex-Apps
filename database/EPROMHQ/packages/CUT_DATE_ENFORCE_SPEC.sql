
  CREATE OR REPLACE EDITIONABLE PACKAGE "EPROMHQ"."CUT_DATE_ENFORCE" AS

--CURSOR CUT_CR IS
--select cd.cutdate,lm.site_code,year,month from tms_cut_dates cd
--join tms_location_map lm on cd.locationid = lm.tms_id
--where cd.month >= mon(sysdate-90) and cd.year >= year(sysdate-90);

PROCEDURE ENFORCE_CUT_DATE_leave;

PROCEDURE ENFORCE_CUT_DATE_permission;

PROCEDURE ENFORCE_CUT_DATE_mission;

PROCEDURE ENFORCE_CUT_DATE_overtime;


END CUT_DATE_ENFORCE;
/
