#!/bin/bash
# vim: ts=4:sw=4

. ~/plescripts/plelib.sh
. ~/plescripts/dblib.sh
. ~/plescripts/global.cfg
EXEC_CMD_ACTION=EXEC

typeset -r ME=$0
typeset -r str_usage=\
"Usage : $ME"

typeset oracle_sid=undef

while [ $# -ne 0 ]
do
	case $1 in
		-emul)
			EXEC_CMD_ACTION=NOP
			shift
			;;

		-oracle_sid=*)
			oracle_sid=${1##*=}
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

#ple_enable_log

script_banner $ME $*

if [ "$oracle_sid" == undef ]
then
	exit_if_ORACLE_SID_not_defined
else
	export ORACLE_SID=$oracle_sid
	ORAENV_ASK=NO . oraenv
fi

sqlplus_cmd "$(set_sql_cmd "startup")"
LN

sqlplus_cmd "$(set_sql_cmd "@$HOME/plescripts/db/sql/lspdbs.sql")"
LN
