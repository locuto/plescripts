-- vim: ts=4:sw=4

--	Je pars du principe que sur un serveur il n'y a qu'un seul CDB, donc
--	db_recovery_file_dest_size aura max_percent (=90%) de la taille de la FRA.

set ver off
define username=ple
define tbs='&username.tbs'

set serveroutput on size unlimited
declare
LN constant char(1) := chr(10);

max_percent	constant number := 90;

--	Constantes pour la fonction exec :
on_error_raise		constant pls_integer := 1;
on_error_continue	constant pls_integer := 2;

--
procedure p( b varchar2 )
as
begin
	dbms_output.put_line( b );
end p;

--
procedure exec( cmd varchar2, on_error pls_integer default on_error_raise )
as
begin
	p( 'SQL> '||cmd||';' );
	execute immediate cmd;
	p( '-- success.'||LN );
exception
	when others then
		if on_error = on_error_raise
		then
			p( '-- Failed : '||sqlerrm||LN );
			raise;
		else
			p( '-- Warning : '||sqlerrm||LN );
		end if;
end exec;

--
function get_dg_size_mb( dg_name varchar2 )
	return number
as
	l_dg_size_mb	number;
begin

	select
		total_mb
	into
		l_dg_size_mb
	from
		v$asm_diskgroup
	where
		name = upper( dg_name )
	;

	p( 'Size disk group '||dg_name||' = '||l_dg_size_mb||'Mb' );

	return l_dg_size_mb;

end get_dg_size_mb;

--
procedure main( dg_fra_name varchar2 )
as
	fra_size_mb	constant number := round( get_dg_size_mb( dg_fra_name ) * (max_percent/100) );
begin
	p( 'Recovery size '||max_percent||'% of '||dg_fra_name );
	exec( 'alter system set db_recovery_file_dest_size='||fra_size_mb||'M scope=both sid=''*''' );
end main;

--
begin
	main( 'FRA' );
end;
/
