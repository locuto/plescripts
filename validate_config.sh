#!/bin/bash

#	ts=4	sw=4

. ~/plescripts/plelib.sh
. ~/plescripts/global.cfg
EXEC_CMD_ACTION=EXEC

typeset -r ME=$0
typeset -r str_usage=\
"Usage : $ME
Ce script vérifie le l'OS host remplie les conditions nécessaire au bon
fonctionnement de la démo."

info "$ME $@"

typeset db=undef

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

typeset -i count_errors=0

line_separator
info -n "Test l'existence de '$HOME/plescripts' "
if [ ! -d "$HOME/plescripts" ]
then
	info -f "[$KO]"
	error "	Ce répertoire doit contenir tous les scripts récupérés depuis GitHub."
	count_errors=count_errors+1
else
	info -f "[$OK]"
fi

if [ $type_shared_fs == nfs ]
then
	info -n "Test l'existence de '$HOME/ISO/$oracle_install' "
	if [ ! -d "$HOME/ISO/$oracle_install" ]
	then
		info -f "[$KO]"
		error "	Ce répertoire doit contenir les zips d'Oracle et du Grid."
		count_errors=count_errors+1
	else
		info -f "[$OK]"
	fi
	LN
fi

if [ $type_shared_fs == vbox ]
then
	info -n "Test l'existence de '$HOME/$oracle_install/database/runInstaller' "
	if [ ! -f "$HOME/$oracle_install/database/runInstaller" ]
	then
		info -f "[$KO]"
		error "	Ce répertoire doit contenir les fichiers dézipés d'Oracle."
		count_errors=count_errors+1
	else
		info -f "[$OK]"
	fi
	info -n "Test l'existence de '$HOME/$oracle_install/grid/runInstaller' "
	if [ ! -f "$HOME/$oracle_install/grid/runInstaller" ]
	then
		info -f "[$KO]"
		error "	Ce répertoire doit contenir les fichiers dézipés du Grid."
		count_errors=count_errors+1
	else
		info -f "[$OK]"
	fi
	LN
fi

if [ $type_shared_fs == nfs ]
then
	if [ $plescripts_ok -eq 0 ]
	then
		info "$client_hostname doit exporter via NFS les répertoires :"
		info -n "	- $HOME/plescripts "
		grep "$HOME/plescripts" /etc/exports >/dev/null 2>&1
		if [ $? -ne 0 ]
		then
			count_errors=count_errors+1
			info -f "[$KO]"
		else
			info -f "[$OK]"
		fi
	fi

	if [ $zip_orcl_grid_ok -eq 0 ]
	then
		info -n "	- $HOME/ISO/$oracle_install "
		grep "$HOME/ISO/$oracle_install" /etc/exports >/dev/null 2>&1
		if [ $? -ne 0 ]
		then
			count_errors=count_errors+1
			info -f "[$KO]"
		else
			info -f "[$OK]"
		fi
	fi
	LN
fi

line_separator
info -n "Test l'existence de $full_linux_iso_name "
if [ ! -f "$full_linux_iso_name" ]
then
	info -f "[$KO]"
	error "L'ISO d'installation d'Oracle Linux 7 n'existe pas."
	count_errors=count_errors+1
else
	info -f "[$OK]"
fi
LN

line_separator
info "Validation de resolv.conf :"
info -n " - nameserver $infra_ip "
if grep -q "^nameserver.*${infra_ip}" /etc/resolv.conf
then
	info -f "[$OK]"
else
	info -f "[$KO]"
	count_errors=count_errors+1
fi

info -n " - search $infra_domain .* "
if grep -q "^search.*${infra_domain}.*" /etc/resolv.conf
then
	info -f "[$OK]"
else
	info -f "[$KO]"
	count_errors=count_errors+1
fi
LN

line_separator
info -n "~/plescripts/shell dans le path "
if $(test_if_cmd_exists llog)
then
	info -f "[$OK]"
else
	info -f "[$KO]"
	count_errors=count_errors+1
fi
LN

line_separator
function in_path
{
	typeset -r cmd=$1

	typeset -r msg=$(printf "%-10s " $cmd)
	info -n "$msg"
	if $(test_if_cmd_exists $cmd)
	then
		info -f "[$OK]"
	else
		count_errors=count_errors+1
		info -f "[$KO]"
	fi
}

in_path VBoxManage
in_path nc
in_path ssh
in_path git
LN

line_separator
info "Positionne les acls sur ~/plescripts"
# Pour supprimer les acls : setfacl -Rb ~/plescripts/
exec_cmd -c setfacl -Rm d:g:users:rwx $HOME/plescripts
LN

line_separator
if [ $count_errors -ne 0 ]
then
	warning "$count_errors erreurs."
	info "Corriger les erreurs avant de continuer."
	exit 1
else
	info "Configuration conforme."
	exit 0
fi

