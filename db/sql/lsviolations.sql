--	vim: ts=4:sw=4
--	sqldevelpper pas sqlplus
select
	*
from
	pdb_plug_in_violations
where
	status != 'RESOLVED'
;
