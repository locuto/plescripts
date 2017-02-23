#!/bin/bash
# vim: ts=4:sw=4

. ~/plescripts/plelib.sh
. ~/plescripts/dblib.sh
. ~/plescripts/gilib.sh
. ~/plescripts/global.cfg
EXEC_CMD_ACTION=EXEC

typeset -r ME=$0

typeset db=undef
typeset pdb=undef
typeset from_pdb=default
typeset	from_samples=no
typeset	create_wallet=yes
typeset is_seed=no
typeset admin_user=pdbadmin
typeset admin_pass=$oracle_password

typeset -r str_usage=\
"Usage :
$ME
	-db=name
	-pdb=name
	[-is_seed]       Seed pdb
	[-from_samples]	 Clone pdb from pdb_samples
	[-from_pdb=name] Clone pdb from name
	[-no_wallet]     Do not use Wallet Manager for pdb connection.
	[-admin_user=$admin_user]
	[-admin_pass=$admin_pass]

Ex create a seed PDB :
$ME -db=$db -pdb=pdb_samples -from_pdb=pdb01 -is_seed

Ex create a PDB from pdb$seed
$ME -db=$db -pdb=pdb666

Ex create a PDB from pdb$seed
$ME -db=$db -pdb=pdb666

Ex create a PDB from pdb_samples
$ME -db=$db -pdb=pdb666 -from_samples
"

while [ $# -ne 0 ]
do
	case $1 in
		-emul)
			EXEC_CMD_ACTION=NOP
			shift
			;;

		-db=*)
			db=$(to_lower ${1##*=})
			shift
			;;

		-pdb=*)
			pdb=$(to_lower ${1##*=})
			shift
			;;

		-from_pdb=*)
			from_pdb=$(to_lower ${1##*=})
			shift
			;;

		-from_samples)
			from_samples=yes
			shift
			;;

		-is_seed)
			is_seed=yes
			shift
			;;

		-no_wallet)
			create_wallet=no
			shift
			;;

		-admin_user=*)
			admin_user=${1##*=}
			shift
			;;

		-admin_pass=*)
			admin_pass=${1##*=}
			shift
			;;

		-h|-help|help)
			info "$str_usage"
			LN
			exit 1
			;;

		*)
			error "Arg '$1' invalid."
			LN
			info "$str_usage"
			exit 1
			;;
	esac
done

ple_enable_log

script_banner $ME $*

must_be_user oracle

exit_if_param_undef db	"$str_usage"
exit_if_param_undef pdb	"$str_usage"

exit_if_database_not_exists $db

exit_if_ORACLE_SID_not_defined

function clone_pdb_pdbseed
{
	function ddl_create_pdb
	{
		set_sql_cmd "whenever sqlerror exit 1;"
		set_sql_cmd "create pluggable database $pdb admin user $admin_user identified by $admin_pass;"
	}
	sqlplus_cmd "$(ddl_create_pdb)"
	[ $? -ne 0 ] && exit 1 || true
}

# $1 pdb name
function clone_from_pdb
{
	function ddl_clone_from_pdb
	{
		set_sql_cmd "whenever sqlerror exit 1;"
		set_sql_cmd "create pluggable database $pdb from $1;"
	}
	sqlplus_cmd "$(ddl_clone_from_pdb $1)"
	[ $? -ne 0 ] && exit 1 || true

}

# Primary database : no parameter
# Physical database : -physical
function pdb_seed_ro_and_save_state
{
	#	Sur un dataguard le PDB doit être ouvert pour être clonable.
	#	Il sera donc un RO comme PDB$SEED.
	#	Il n'a pas de services, donc son état doit être sauvegardé sur toutes
	#	les bases d'un dataguard.
	set_sql_cmd "prompt Ferme la PDB pour être sur de son état."
	set_sql_cmd "alter pluggable database pdb_samples close instances=all;"
	set_sql_cmd "whenever sqlerror exit 1;"
	if [ "$1" != -physical ]
	then
		set_sql_cmd "alter pluggable database pdb_samples open read write instances=all;"
		set_sql_cmd "alter pluggable database pdb_samples close instances=all;"
	fi
	set_sql_cmd "alter pluggable database pdb_samples open read only instances=all;"
	set_sql_cmd "alter pluggable database pdb_samples save state instances=all;"
}

function create_pdb_services
{
	line_separator
	info "Create services"
	if [ $dataguard == yes ]
	then
		for (( i=0; i < ${#physical_list[@]}; ++i ))
		do
			add_dynamic_cmd_param "-db=$primary"
			add_dynamic_cmd_param "-pdb=$pdb"
			add_dynamic_cmd_param "-standby=${physical_list[i]}"
			add_dynamic_cmd_param "-standby_host=${stby_server_list[i]}"
			exec_dynamic_cmd "./create_srv_for_dataguard.sh"
			LN
		done
	else
		if [ $gi_count_nodes -eq 1 ]
		then
			exec_cmd ./create_srv_for_single_db.sh -db=$db -pdb=$pdb
		else
			typeset poolName="$(srvctl config database -db $db	|\
								grep "^Server pools:" | awk '{ print $3 }')"
			exec_cmd ./create_srv_for_rac_db.sh	\
									-db=$db -pdb=$pdb -poolName=$poolName
		fi
	fi
}

# Si un PDB est clonée depuis un PDB existant, il faut supprimer tous les
# services du pdb existant qui sont dans le PDB cloné.
function sqlcmd_remove_services_from_cloned_pdb
{
	set_sql_cmd "alter pluggable database $pdb close immediate instances=all;"
	set_sql_cmd "alter pluggable database $pdb open read write instances=all;"
	set_sql_cmd "alter session set container=$pdb;"
	echo "set serveroutput on"
	echo "begin"
	echo "    for s in ( select name from all_services where name != '$(to_lower $pdb)' )"
	echo "    loop"
	echo "        dbms_output.put_line( 'Remove service : '||s.name );"
	echo "        dbms_service.delete_service( s.name );"
	echo "    end loop;"
	echo "end;"
	echo "/"
}

function create_wallet
{
	line_separator
	exec_cmd "~/plescripts/db/add_sysdba_credential_for_pdb.sh -db=$db -pdb=$pdb"
	if [ $dataguard == yes ]
	then
		for (( i=0; i < ${#physical_list[@]}; ++i ))
		do
			exec_cmd "ssh ${stby_server_list[i]}	\
				'. .bash_profile;	\
				~/plescripts/db/add_sysdba_credential_for_pdb.sh	\
									-db=${physical_list[i]} -pdb=$pdb'"
			LN
		done
	fi
}

if [[ $is_seed == yes ]]
then
	if [ $from_samples == yes ]
	then
		error "-from_samples incompatible with -is_seed"
		LN
		exit 1
	fi

	if [ $from_pdb == default ]
	then
		error "-from_pdb missing with -is_seed"
		LN
		exit 1
	fi

	create_wallet=no
fi

if [[ $from_samples == yes && $from_pdb != default ]]
then
	error "Used -from_samples or -from_pdb"
	LN
	exit 1
fi

typeset	-r dataguard=$(dataguard_config_available)

if [[ $dataguard == yes && $gi_count_nodes -gt 1 ]]
then
	error "RAC + Dataguard not supported."
	exit 1
fi

if [ $dataguard == yes ]
then
	typeset -r primary="$(read_primary_name)"
	if [ "$primary" != "$db" ]
	then
		error "db=$db, primary name is $primary"
		error "Execute script on primary database."
		LN
		exit 1
	fi

	typeset -a physical_list
	typeset -a stby_server_list
	load_stby_database
fi

info "On database $db create pdb $pdb"
if [ $dataguard == yes ]
then
	info "Physical standby : ${physical_list[*]}"
	info "Servers          : ${stby_server_list[*]}"
fi
LN

line_separator
[ $from_samples == yes ] && from_pdb=pdb_samples || true

[ $from_pdb == default ] && clone_pdb_pdbseed || clone_from_pdb $from_pdb
LN

for stby in ${physical_list[*]}
do
	exec_cmd "dgmgrl -silent sys/$oracle_password 'show database ${stby}'"
	LN
done

if [ $from_pdb != default ]
then
	sqlplus_cmd "$(sqlcmd_remove_services_from_cloned_pdb)"
fi

if [ $is_seed == yes ]
then
	sqlplus_cmd "$(pdb_seed_ro_and_save_state)"
else
	create_pdb_services
fi

if [ $dataguard == yes ]
then
	function add_temp_tbs_to
	{
		set_sql_cmd "alter session set container=$1;"
		set_sql_cmd "alter tablespace temp add tempfile;"
	}

	line_separator
	info "12cR1 : temporary tablespace not created."
	for stby_name in ${physical_list[*]}
	do
		sqlplus_cmd_with sys/$oracle_password@$stby_name as sysdba	\
											"$(add_temp_tbs_to $pdb)"
		if [ $is_seed == yes ]
		then
			sqlplus_cmd_with sys/$oracle_password@$stby_name as sysdba	\
								"$(pdb_seed_ro_and_save_state -physical)"
		fi
		LN
	done
fi

[ $create_wallet == yes ] && create_wallet || true

if [ $from_samples == yes ]
then
	info "Unlock sample schemas."
	exec_cmd ~/plescripts/db/sample_schemas_unlock_accounts.sh -db=$db -pdb=$pdb
	LN
fi
