#!/bin/bash
# vim: ts=4:sw=4

. ~/plescripts/plelib.sh
. ~/plescripts/global.cfg
EXEC_CMD_ACTION=EXEC

typeset db_type=undef

typeset	-r	ME=$0
typeset -r	str_usage=\
"Usage $ME -db_type=[single|rac|single_fs]"

while [ $# -ne 0 ]
do
	case $1 in
		-db_type=*)
			db_type=${1##*=}
			shift
			;;

		-h|-help|help)
			info "$str_usage"
			LN
			exit 1
			;;

		*)
			error "'$1' invalid."
			LN
			info "$str_usage"
			exit 1
			;;
	esac
done

exit_if_param_invalid db_type "single rac single_fs" "$str_usage"

fake_exec_cmd cd ~/plescripts/oracle_preinstall
cd ~/plescripts/oracle_preinstall
LN

info "Workaround yum error : [Errno 256] No more mirrors to try."
exec_cmd systemctl restart nfs-mountd.service
exec_cmd umount /mnt$infra_olinux_repository_path
timing 2
exec_cmd mount /mnt$infra_olinux_repository_path
timing 2
LN
exec_cmd "~/plescripts/yum/clean_cache.sh"
LN

exec_cmd "./01_create_oracle_users.sh -release=$oracle_release -db_type=$db_type"
LN

exec_cmd "./02_install_some_rpms.sh"
LN

if [ $db_type != single_fs ]
then
	exec_cmd "./03_install_oracleasm.sh"
	LN
fi

exec_cmd "./04_apply_os_prerequis.sh -db_type=$db_type"
LN

exit
