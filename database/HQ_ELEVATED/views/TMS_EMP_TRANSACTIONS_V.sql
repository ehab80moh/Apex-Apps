
  CREATE OR REPLACE FORCE EDITIONABLE VIEW "HQ_ELEVATED"."TMS_EMP_TRANSACTIONS_V" ("EMPLOYEENUMBER", "TRANS_DATE", "TRANS_TYPE", "LOCATIONNAME") AS
  select employeenumber,to_date(to_char(date_,'dd-mm-yyyy hh24:mi'),'dd-mm-yyyy hh24:mi') trans_date,decode(type,'true','IN','OUT') trans_type ,locationname
from tms_emp_transactions
group by employeenumber,to_char(date_,'dd-mm-yyyy hh24:mi'),type,locationname;
