#!/bin/bash
# vim: ts=4:sw=4

. ~/plescripts/plelib.sh
. ~/plescripts/global.cfg
EXEC_CMD_ACTION=EXEC

typeset -r ME=$0
typeset -r PARAMS="$*"
typeset -r str_usage="Usage : $ME"

must_be_user root

while [ $# -ne 0 ]
do
	case $1 in
		-emul)
			EXEC_CMD_ACTION=NOP
			first_args=-emul
			shift
			;;

		*)
			error "Arg '$1' invalid."
			LN
			info "$str_usage"
			exit 1
			;;
	esac
done

typeset -r service=plememstats
typeset -r service_file=/usr/lib/systemd/system/$service.service

if [ -f $service_file ]
then
	info "$service service exists."
	exit 0
fi

info "Create systemd service $service"

cat <<EOS > $service_file
[Unit]
Description=PLE Memory Statistics
Wants=nfs.target
After=nfs.target

[Service]
Type=simple
ExecStart=/root/plescripts/stats/memstats.sh -title=global
ExecStop=/root/plescripts/stats/memstats.sh -stop -title=global
TimeoutStopSec=5

[Install]
WantedBy=multi-user.target
EOS

if [ ! -f $service_file ]
then
	error "Cannot create $service_file !"
	exit 1
fi

info "$service_file created."
exec_cmd "cat $service_file"
LN

[ x"$PLE_STATISTICS" == x ] && PLE_STATISTICS=$PLESTATISTICS || true

if grep -q MEMORY <<< "$PLE_STATISTICS"
then
	info "Enable service"
	exec_cmd "systemctl enable $service"
	LN

	info "Start service"
	exec_cmd "systemctl start $service"
	LN
fi
