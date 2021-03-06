#!/bin/bash
# vim: ts=4:sw=4

. ~/plescripts/plelib.sh
. ~/plescripts/global.cfg
EXEC_CMD_ACTION=EXEC

typeset -r ME=$0
typeset -r PARAMS="$*"

typeset -r str_usage=\
"Usage : $ME"

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

LANG=C

[ ! -d /media/cdrom ] && exec_cmd mkdir /media/cdrom || true
sleep 1
info "mount /media/cdrom"
while true
do
	exec_cmd -c "mount /dev/cdrom /media/cdrom"
	ret=$?
	[ $ret -eq 0 ] && break || true
	[ $ret -eq 32 ] && true || break
	sleep 1
done
LN

exec_cmd "~/plescripts/virtualbox/guest/install_gcc_and_kernel_devel.sh"

info "Execute VBoxLinuxAdditions.run"
fake_exec_cmd cd /media/cdrom
cd /media/cdrom
exec_cmd ./VBoxLinuxAdditions.run
fake_exec_cmd cd -
cd -
LN

exec_cmd umount /media/cdrom
exec_cmd eject
