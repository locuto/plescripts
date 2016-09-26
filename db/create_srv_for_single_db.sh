#!/bin/bash
# vim: ts=4:sw=4

. ~/plescripts/plelib.sh
. ~/plescripts/global.cfg
EXEC_CMD_ACTION=EXEC

typeset -r ME=$0
typeset -r str_usage=\
"Usage : $ME
	-db=str
	-pdbName=str
	[-role=str]        (primary, physical_standby, ${STRIKE}logical_standby, snapshot_standby$NORM)
	[-start=yes]

RAC non pris en compte.
"

info "Running : $ME $*"

typeset db=undef
typeset pdbName=undef
typeset role=undef
typeset start=yes

while [ $# -ne 0 ]
do
	case $1 in
		-emul)
			EXEC_CMD_ACTION=NOP
			first_args=-emul
			shift
			;;

		-db=*)
			db=${1##*=}
			shift
			;;

		-pdbName=*)
			pdbName=$(to_upper ${1##*=})
			shift
			;;

		-role=*)
			role=${1##*=}
			shift
			;;

		-start=*)
			start=${1##*=}
			shift
			;;

		-h|-help|help)
			info "$str_usage"
			LN
			exit 1
			;;

		*)
			error "Arg '$1' unknow."
			LN
			info "$str_usage"
			exit 1
			;;
	esac
done

[[ $db = undef ]] && [[ -v ID_DB ]] && db=$ID_DB
exit_if_param_undef db				"$str_usage"
exit_if_param_undef pdbName			"$str_usage"

case "$role" in
	primary|undef)
		typeset -r prefixService=pdb${pdbName}
		;;

	physical_standby)
		typeset -r prefixService=pdb${pdbName}_stby
		;;

	*)
		error "Role '$role' non pris en compte."
		exit 1
esac


line_separator
info "create service ${prefixService}_oci on pluggable $pdbName (db = $db)."
LN
#	http://docs.oracle.com/database/121/RACAD/hafeats.htm#RACAD7026
#	Creating Services for Application Continuity ssi -failovertype TRANSACTION
#	-replay_init_time par défaut 300s
#	-retention par défaut de 1j pour le 'commit outcome'
#	-failoverretry par défaut 30
#	-failoverdelay 10s entre chaque retry.
#	-notification: FAN is highly recommended—set this value to TRUE to enable FAN for OCI and ODP.Net clients.
#	
#	Creating Services for Transaction Guard : To enable Transaction Guard, but not Application Continuity
#	-commit_outcome TRUE
#	To use Transaction Guard, a DBA must grant permission, as follows:
#	GRANT EXECUTE ON DBMS_APP_CONT;

add_dynamic_cmd_param "add service -service ${prefixService}_oci"
add_dynamic_cmd_param "    -pdb $pdbName -db $db"
if [ $role != undef ]
then
	add_dynamic_cmd_param "    -role           $role"
	add_dynamic_cmd_param "    -policy         automatic"
	add_dynamic_cmd_param "    -failovertype   select"
	add_dynamic_cmd_param "    -failovermethod basic"
	add_dynamic_cmd_param "    -failoverretry  3"
	add_dynamic_cmd_param "    -failoverdelay  60"
	add_dynamic_cmd_param "    -clbgoal        long"
	add_dynamic_cmd_param "    -rlbgoal        throughput"
fi

exec_dynamic_cmd srvctl
LN

if [ $start == yes ]
then
	exec_cmd srvctl start service -service ${prefixService}_oci -db $db
	LN
fi

line_separator
#	Services for Application Continuity (java)
info "create service ${prefixService}_java on pluggable $pdbName (db = $db)"
LN

add_dynamic_cmd_param "add service -service ${prefixService}_java"
add_dynamic_cmd_param "    -pdb $pdbName -db $db"
if [ $role != undef ]
then
	add_dynamic_cmd_param "    -role           $role"
	add_dynamic_cmd_param "    -policy         automatic"
	add_dynamic_cmd_param "    -failovertype   select"
	add_dynamic_cmd_param "    -failovermethod basic"
	add_dynamic_cmd_param "    -failoverretry  3"
	add_dynamic_cmd_param "    -failoverdelay  60"
	add_dynamic_cmd_param "    -clbgoal        long"
	add_dynamic_cmd_param "    -rlbgoal        throughput"
fi

exec_dynamic_cmd srvctl
LN

if [ $start == yes ]
then
	exec_cmd srvctl start service -service ${prefixService}_java  -db $db
	LN
fi