#!/bin/bash
#	ts=4	sw=4

. ~/plescripts/plelib.sh
. ~/plescripts/global.cfg
EXEC_CMD_ACTION=EXEC

typeset -r ME=$0
typeset -r str_usage=\
"Usage : $ME ...."

info "$ME $@"

while [ $# -ne 0 ]
do
	case $1 in
		-emul)
			EXEC_CMD_ACTION=NOP
			first_args=-emul
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

VBoxManage list hostonlyifs | grep vboxnet0 >/dev/null 2>&1
if [ $? -ne 0 ]
then
	info "Create Iface vboxnet0"
	exec_cmd "VBoxManage hostonlyif create"
	exec_cmd "VBoxManage hostonlyif ipconfig vboxnet0 --ip ${infra_network}.1"
else
	info "Iface vboxnet0 exists."
fi
LN