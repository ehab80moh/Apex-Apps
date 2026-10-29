
  CREATE OR REPLACE EDITIONABLE PACKAGE "EPROMHQ"."INV_AUDIT_PKG" AS
  TYPE changes_type IS RECORD
  (
    column_name VARCHAR2(255),
    old_value   VARCHAR2(4000 BYTE),
    new_value   VARCHAR2(4000 BYTE)
  );
END inv_audit_pkg;
/
