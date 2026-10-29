
  CREATE OR REPLACE EDITIONABLE TRIGGER "EPROMHQ"."DEPT_TRG1"
              before insert on dept
              for each row
              begin
                  if :new.deptno is null then
                      select dept_seq.nextval into :new.deptno from sys.dual;
                 end if;
              end;
/
ALTER TRIGGER "EPROMHQ"."DEPT_TRG1" ENABLE;
