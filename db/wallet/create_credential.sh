#!/bin/bash
# vim: ts=4:sw=4

. ~/plescripts/plelib.sh
. ~/plescripts/gilib.sh
. ~/plescripts/db/wallet/walletlib.sh
. ~/plescripts/global.cfg
EXEC_CMD_ACTION=EXEC

typeset -r ME=$0
typeset -r PARAMS="$*"
typeset -r str_usage=\
"Usage : $ME -tnsalias=name -user=name -password=pass [-nolog]

Si le wallet store n'existe pas il est créé.

RAC : prend en charge un 'wallet store' non stocké sur un CFS.

Dataguard : exécuter le script sur tous les nœuds.
"

typeset	tnsalias=undef
typeset	user=undef
typeset	password=undef
typeset	log=yes

#	Dans le cas d'un RAC le script sera exécuté sur tous les
#	nœuds sauf si le flag -local_only est utilisé.
typeset	local_only=no

while [ $# -ne 0 ]
do
	case $1 in
		-emul)
			EXEC_CMD_ACTION=NOP
			shift
			;;

		-tnsalias=*)
			tnsalias=${1##*=}
			shift
			;;

		-user=*)
			user=${1##*=}
			shift
			;;

		-password=*)
			password=${1##*=}
			shift
			;;

		-local_only)
			local_only=yes
			shift
			;;

		-nolog)
			log=no
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

exit_if_param_undef tnsalias	"$str_usage"
exit_if_param_undef user		"$str_usage"
exit_if_param_undef password	"$str_usage"

[ $log == yes ] && ple_enable_log -params $PARAMS || true

if [ ! -d $wallet_path ]
then
	exec_cmd ~/plescripts/db/wallet/create_wallet.sh -nolog
fi

if ! tnsping $tnsalias >/dev/null 2>&1
then
	error "TNS alias '$tnsalias' not exists."
	LN
	exit 1
fi

fake_exec_cmd mkstore -wrl $wallet_path -nologo	\
								-createCredential $tnsalias $user $password
if [ $? -eq 0 ]
then
	mkstore -wrl $wallet_path -nologo	\
							-createCredential $tnsalias $user $password<<-EOP
	$oracle_password
	EOP

	if [[ $gi_count_nodes -gt 1 && $local_only == no ]] && ! wallet_store_on_cfs
	then
		execute_on_other_nodes -c	\
			". .bash_profile;								\
				~/plescripts/db/wallet/create_credential.sh	\
									-nolog					\
									-tnsalias=$tnsalias		\
									-user=$user				\
									-password=$password		\
									-local_only"
	fi
fi
