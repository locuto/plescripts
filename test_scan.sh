#!/bin/bash
# vim: ts=4:sw=4

. ~/plescripts/plelib.sh
. ~/plescripts/global.cfg
EXEC_CMD_ACTION=EXEC

typeset -r ME=$0
typeset -r PARAMS="$*"

typeset scan_name=$1
[ x"$scan_name" == x ] && scan_name=$(olsnodes -c 2>/dev/null)
[ x"$scan_name" == x ] && error "$ME <scan-adress>" && exit 1

if [ $disable_dns_cache == yes ]
then
	info "Stop nscd.service"
	exec_cmd -c sudo systemctl stop nscd.service
	LN
fi

typeset -a	ip_list

line_separator
info "Ping $scan_name"
for i in $( seq 1 3 )
do
	info -n "    ping #${i} "
	ip_list[$((i-1))]=$(ping -c 1 $scan_name | head -2 | tail -1 | sed "s/.*(\([0-9]*\.[0-9]*\.[0-9]*\.[0-9]*\)).*/\1/")
	sleep 1
	LN
done

# $1 indice de l'IP dans ip_list
function test_ip_uniq
{
	typeset -ri indice=$1

	typeset -i count_diffs=0
	typeset -i i=0
	while [ $i -lt ${#ip_list[@]} ]
	do
		if [ $i -ne $indice ]
		then
			[ "${ip_list[$i]}" != "${ip_list[$indice]}" ] && count_diffs=count_diffs+1
		fi
		i=i+1
	done

	[ $count_diffs -eq 2 ] && return 0 || return 1
}

info "Nombre d'IPs : ${#ip_list[@]}"
typeset	-i	dup=0
typeset -i	i=0
while [ $i -lt ${#ip_list[@]} ]
do
	info -n "IP $(( i + 1 )) : ${ip_list[$i]}"
	test_ip_uniq $i
	if [ $? -ne 0 ]
	then
		info -f " : dupliquée."
		dup=dup+1
	else
		LN
	fi
	i=i+1
done
LN

if [ $disable_dns_cache == yes ]
then
	info "Start nscd.service"
	exec_cmd -c sudo systemctl start nscd.service
	LN
fi

info "$dup ping sur la même IP"
LN

if [ $dup -eq 3 ]
then
	warning "Problème cache DNS (nscd) ?"
	LN
fi

line_separator
exec_cmd -c host $scan_name
if [ $? -ne 0 ]
then
	info "La commande host ne fonctionne pas quand"
	info "le DNS n'est pas en mode récursion."
fi
LN

info "On RAC node : cluvfy comp scan"
LN
