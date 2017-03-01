#!/bin/bash
# vim: ts=4:sw=4

. ~/plescripts/plelib.sh
. ~/plescripts/global.cfg
EXEC_CMD_ACTION=EXEC

typeset -r ME=$0
typeset -r str_usage=\
"Usage : $ME

Effectue une sauvegarde locale du dépôt yum de $infra_hostname.
Doit être exécuté sur $client_hostname."

script_banner $ME $*

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

must_be_executed_on_server "$client_hostname"

function create_backup_on_server_infra
{
	info "Create $backup_name on $infra_hostname"
	exec_cmd "ssh ${infra_conn} \"cd /repo; tar cf - OracleLinux |\
												gzip -c > $backup_name\""
	LN
}

function copy_backup_to_local_host
{
	info "Copy $backup_name to $client_hostname"
	exec_cmd "scp ${infra_conn}:/repo/$backup_name $full_backup_name"
	LN
}

# return 0 OK, else 1 KO
# Même avec scp la copie peut être corrompue.
function validates_local_backup
{
	info "Validates local backup $backup_name"
	exec_cmd -c "gzip -dc $full_backup_name > /dev/null"
}

typeset -r backup_name="yum_repo.tar.gz"
typeset -r full_backup_name="$iso_olinux_path/$backup_name"
if [ -f "$full_backup_name" ]
then
	exec_cmd ls -l $full_backup_name
	confirm_or_exit "Backup exists. Remove"
fi

create_backup_on_server_infra

copy_backup_to_local_host

if ! validates_local_backup
then
	LN
	info "Validates $backup_name on $infra_hostname"
	exec_cmd -c "ssh ${infra_conn} 'gzip -dc /repo/$backup_name > /dev/null'"
	if [ $? -ne 0 ]
	then
		error "Rerun the scripts."
		LN
		exit 1
	fi

	info "$backup_name valid on $infra_hostname"
	LN

	copy_backup_to_local_host

	if ! validates_local_backup
	then
		error "scp error ??"
		exit 1
	fi
fi
LN

info "Remove $backup_name from $infra_hostname"
exec_cmd "ssh ${infra_conn} \"rm -rf /repo/$backup_name\""
LN
