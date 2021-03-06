#!/bin/bash
# vim: ts=4:sw=4

. ~/plescripts/plelib.sh
. ~/plescripts/global.cfg
EXEC_CMD_ACTION=EXEC

typeset -r ME=$0
typeset -r PARAMS="$*"
typeset -r str_usage=\
"Ne pas utiliser ce script directement mais :
./uninstall.sh -oracle
"

while [ $# -ne 0 ]
do
	case $1 in
		-emul)
			EXEC_CMD_ACTION=NOP
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

must_be_user oracle

exit_if_file_not_exists /mnt/oracle_install/database/runInstaller "mount /mnt/oracle_install"

info "deinstall oracle"
fake_exec_cmd /mnt/oracle_install/database/runInstaller -deinstall -home $ORACLE_HOME CR CR y
if [ $? -eq 0 ]
then
/mnt/oracle_install/database/runInstaller -deinstall -home $ORACLE_HOME<<EOS

y
EOS
fi
LN

line_separator
exec_cmd "rm -rf ${ORACLE_BASE%/*}/oraInventory"
exec_cmd "rm -rf $ORACLE_HOME/*"
LN

if command_exists olsnodes
then
	# En 12.2 l'ORACLE_HOME des autres nœuds ne sont pas supprimés.
	while read node
	do
		[[ x"$node" == x || "$node" == $(hostname -s) ]] && continue || true

		exec_cmd "ssh $node '. .bash_profile && rm -rf ${ORACLE_BASE%/*}/oraInventory || true'</dev/null"
		exec_cmd "ssh $node '. .bash_profile && rm -rf $ORACLE_HOME/* || true'</dev/null"
		LN
	done<<<"$(olsnodes)"
fi

exit 0
