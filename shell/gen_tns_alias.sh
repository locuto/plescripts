#!/bin/bash
# vim: ts=4:sw=4

. ~/plescripts/plelib.sh
. ~/plescripts/global.cfg
EXEC_CMD_ACTION=EXEC

typeset -r ME=$0
typeset -r str_usage=\
"Usage : ${ME##*/}
	-service=name                       Nom du service.
	-server_list=\"server1 server2 ...\"  Liste des serveurs.

Créé un alias TNS du même nom que le service.
La définition de l'alias est affichée sur la canal 1.
Si il y a plus d'un serveur dans -server_list alors configuration dataguard.

Exemples :
 - Alias pour un RAC       
	${ME##*/} -service=pdbFOO01_java -server_list=\"foo-scan\"
 - Alias pour une SINGLE
	${ME##*/} -service=pdbFOO_java -server_list=\"srvfoo01\"
 - Alias pour un dataguard
	${ME##*/} -service=pdbDAISY01_java -server_list=\"srvdaisy01 srvdonald01\"
"

typeset service=undef
typeset server_list=undef

while [ $# -ne 0 ]
do
	case $1 in
		-emul)
			EXEC_CMD_ACTION=NOP
			first_args=-emul
			shift
			;;

		-service=*)
			service=${1##*=}
			shift
			;;

		-server_list=*)
			server_list=${1##*=}
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

exit_if_param_undef service		"$str_usage"
exit_if_param_undef server_list	"$str_usage"

typeset	-ri	count_servers=$(echo "$server_list" | wc -w)

function get_address
{
	for server in $server_list
	do
		echo "			(ADDRESS = (PROTOCOL = TCP) (HOST = $server) (PORT = 1521) )"
	done
}

#	Ouvre la section DESCRIPTION, des options supplémentaires sont affichées pour
#	un dataguard.
function open_section_description
{
	echo "	(DESCRIPTION ="

	[ $count_servers -eq 1 ] && return 0

	echo "		(CONNECT_TIMEOUT= 4) (RETRY_COUNT=20)(RETRY_DELAY=3)"
	echo "		(FAILOVER=on)"
	echo "		(LOAD_BALANCE=off)"
}

cat<<EOS
$(to_upper $service) =
$(open_section_description)
		(ADDRESS_LIST=
$(get_address)
		)
		(CONNECT_DATA =
			(SERVER = DEDICATED)
			(SERVICE_NAME = $service)
		)
	)
EOS