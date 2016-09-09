#!/bin/bash
# vim: ts=4:sw=4

. ~/plescripts/plelib.sh
. ~/plescripts/global.cfg
EXEC_CMD_ACTION=EXEC
PAUSE=ON

typeset -r ME=$0
typeset -r str_usage=\
"Usage : $ME
	-primary=name      Nom de la base primaire (doit exister)
	-standby=name      Nom de la base standby (sera créée)
	-standby_host=name Nom du serveur ou résidera la standby

	-skip_setup_primary
	-skip_configuration
	-skip_duplicate
"	 

info "Running : $ME $*"

typeset primary=undef
typeset standby=undef
typeset standby_host=undef
typeset skip_configuration=no
typeset skip_setup_primary=no
typeset skip_duplicate=no

while [ $# -ne 0 ]
do
	case $1 in
		-emul)
			EXEC_CMD_ACTION=NOP
			first_args=-emul
			shift
			;;

		-primary=*)
			primary=$(to_upper ${1##*=})
			shift
			;;

		-standby=*)
			standby=$(to_upper ${1##*=})
			shift
			;;

		-standby_host=*)
			standby_host=${1##*=}
			shift
			;;

		-skip_configuration)
			skip_configuration=yes
			shift
			;;

		-skip_setup_primary)
			skip_setup_primary=yes
			shift
			;;

		-skip_duplicate)
			skip_duplicate=yes
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

exit_if_param_undef primary			"$str_usage"
exit_if_param_undef standby			"$str_usage"
exit_if_param_undef standby_host	"$str_usage"

typeset -r	SQL_PROMPT="prompt SQL>"

#	$@ contient une commande à exécuter.
#	La fonction n'exécute pas la commande elle :
#		- affiche le prompt SQL> suivi de la commande.
#		- affiche sur la seconde ligne la commande.
#
#	Le but étant de construire dans une fonction 'les_commandes' l'ensemble des
#	commandes à exécuter à l'aide de to_exec.
#	La fonction 'les_commandes' donnera la liste des commandes à la fonction run_sqlplus
function to_exec
{
cat<<WT
prompt
$SQL_PROMPT $@;
$@
WT
}

#	Exécute les commandes "$@" avec sqlplus en sysdba
function run_sqlplus
{
	fake_exec_cmd sqlplus -s sys/$oracle_password as sysdba
	printf "set echo off\nset timin on\n$@\n" | sqlplus -s sys/$oracle_password as sysdba
	LN
}

function run_sqlplus_on_standby
{
	fake_exec_cmd sqlplus -s sys/$oracle_password@${standby} as sysdba
	printf "set echo off\nset timin on\n$@\n" | sqlplus -s sys/$oracle_password@${standby} as sysdba
	LN
}

function result_of_query
{
	typeset -r	query="$1"
	info "run $query"
	printf "whenever sqlerror exit 1\nset term off echo off feed off heading off\n$query" | sqlplus -s sys/$oracle_password as sysdba
}

function exec_query
{
	typeset -r	query="$1"
	info "run $query"
	printf "whenever sqlerror exit 1\n$query" | sqlplus -s sys/$oracle_password as sysdba
}

function set_primary_cfg
{
	to_exec "alter system set standby_file_management='AUTO' scope=both sid='*';"

	to_exec "alter system set log_archive_config='dg_config=($primary,$standby)' scope=both sid='*';"

	to_exec "alter system set fal_server='$standby' scope=both sid='*';"

	to_exec "alter system set log_archive_dest_1='location=use_db_recovery_file_dest valid_for=(all_logfiles,all_roles) db_unique_name=$primary' scope=both sid='*';"

	to_exec "alter system set log_archive_dest_2='service=$standby async valid_for=(online_logfiles,primary_role) db_unique_name=$standby' scope=both sid='*';"

	echo prompt
	echo prompt --	Paramètres nécessitant un arrêt/démarrage :
	to_exec "alter system set remote_login_passwordfile='EXCLUSIVE' scope=spfile sid='*';"

	to_exec "alter system set db_file_name_convert='+DATA/$standby/','+DATA/$primary/','+FRA/$standby/','+FRA/$primary/' scope=spfile sid='*';"

	to_exec "alter system set log_file_name_convert='+DATA/$standby/','+DATA/$primary/','+FRA/$standby/','+FRA/$primary/' scope=spfile sid='*';"

	to_exec "alter database force logging;"

	to_exec "shutdown immediate"
	to_exec "startup"
}

function create_standby_redo_logs
{
	typeset -ri nr=$1
	typeset -r	redo_size_mb="$2"

	for i in $( seq $nr )
	do
		to_exec "alter database add standby logfile size $redo_size_mb;"
	done
}

#	$1	nom du servue
#	$2	nom de l'hôte
#
#	Créé un alias ayant pour nom $2
function get_alias_for
{
	typeset	-r	service_name=$1
	typeset	-r	host_name=$2
cat<<EOA
$service_name =
	(DESCRIPTION =
		(ADDRESS =
			(PROTOCOL = TCP)
			(HOST = $host_name)
			(PORT = 1521)
		)
		(CONNECT_DATA =
			(SERVER = DEDICATED)
			(SERVICE_NAME = $service_name)
		)
	)
EOA
}

function get_alias_for_primary
{
	get_alias_for $primary $primary_host
}

function get_alias_for_standby
{
	get_alias_for $standby $standby_host
}

function get_primary_sid_list_listener_for
{
	typeset	-r	g_dbname=$1
	typeset -r	sid_name=$2
	typeset	-r	orcl_home="$3"

cat<<EOL

#	Added by bibi
SID_LIST_LISTENER =
	(SID_LIST =
		(SID_DESC =
			(GLOBAL_DBNAME = $g_dbname)
			(ORACLE_HOME = $orcl_home)
			(SID_NAME = $sid_name)
		)
  )
#	End bibi
EOL
}

function primary_listener_add_static_entry
{
	typeset -r primary_sid_list=$(get_primary_sid_list_listener_for $primary $primary "$ORACLE_HOME")
	info "Ajout d'un entrée statique dans le listener de la primaire."
	info "Sur une SINGLE GLOBAL_DBNAME == SID_NAME"

typeset -r script=/tmp/setup_listener.sh
cat<<EOS > $script
#!/bin/bash

grep -q SID_LIST_LISTENER \$TNS_ADMIN/listener.ora
if [ \$? -eq 0 ]
then
	echo "listener déjà configuré."
	exit 0
fi

echo "Configuration :"
cp \$TNS_ADMIN/listener.ora \$TNS_ADMIN/listener.ora.bibi.backup
echo "$primary_sid_list" >> \$TNS_ADMIN/listener.ora
lsnrctl reload
EOS
	exec_cmd "chmod ug=rwx $script"
	exec_cmd "sudo -u grid -i $script"
	LN
}

function standby_listener_add_static_entry
{
	typeset -r standby_sid_list=$(get_primary_sid_list_listener_for $standby $standby "$ORACLE_HOME")
	info "Ajout d'un entrée statique dans le listener de la standby."
	info "Sur une SINGLE GLOBAL_DBNAME == SID_NAME"
typeset -r script=/tmp/setup_listener.sh
cat<<EOS > $script
#!/bin/bash

grep -q SID_LIST_LISTENER \$TNS_ADMIN/listener.ora
if [ \$? -eq 0 ]
then
	echo "listener déjà configuré."
	exit 0
fi

echo "Configuration :"
cp \$TNS_ADMIN/listener.ora \$TNS_ADMIN/listener.ora.bibi.backup
echo "$standby_sid_list" >> \$TNS_ADMIN/listener.ora
lsnrctl reload
EOS
	exec_cmd chmod ug=rwx $script
	exec_cmd "scp $script $standby_host:$script"
	exec_cmd "ssh -t $standby_host sudo -u grid -i $script"
	LN
}

function add_standby_redolog
{
	info "Add stdby redo log"
	typeset		redo_size_mb=undef
	typeset	-i	nr_redo=-1
	read redo_size_mb nr_redo <<<"$(result_of_query "select distinct round(bytes/1024/1024)||'M', count(*) from v\$log group by bytes;" | tail -1)"
	info "La base possède $nr_redo redos de $redo_size_mb"

	typeset -ri nr_stdby_redo=nr_redo+1
	info " --> Ajout de $nr_stdby_redo standby redos de $redo_size_mb (Nombre à vérifier je ne suis pas certain...)"
	run_sqlplus "$(create_standby_redo_logs $nr_stdby_redo $redo_size_mb)"
	LN

	exec_query "set lines 130 pages 45\ncol member for a45\nselect * from v\$logfile order by type, group#;"
	LN
}

function setup_tnsnames
{
	exec_cmd "rm -f $tnsnames_file"
	if [ ! -f $tnsnames_file ]
	then
		info "Create file $tnsnames_file"
		info "Add alias $primary"
		get_alias_for_primary > $tnsnames_file
		echo " " >> $tnsnames_file
		info "Add alias $standby"
		get_alias_for_standby >> $tnsnames_file
		LN
		info "Copy tnsname.ora from $primary_host to $standby_host"
		exec_cmd "scp $tnsnames_file $standby_host:$tnsnames_file"
		LN
	else
		error "L'existence du fichier tnsnames.ora n'est pas encore prise en compte."
		exit 1
	fi
}

function start_standby
{
	info "Copie du fichier password."
	exec_cmd scp $ORACLE_HOME/dbs/orapw${primary} ${standby_host}:$ORACLE_HOME/dbs/orapw${standby}
	LN

	line_separator
	info "Création du répertoire $ORACLE_BASE/$standby/adump sur $standy_host"
	exec_cmd -c "ssh $standby_host mkdir -p $ORACLE_BASE/admin/$standby/adump"
	LN

	test_pause

	line_separator
	info "Configure et démarre $standby sur $standby_host (configuration minimaliste.)"
	ssh -t -t $standby_host<<EOS
	rm -f $ORACLE_HOME/dbs/sp*${standby}* $ORACLE_HOME/dbs/init*${standby}*
	echo "db_name='$standby'" > $ORACLE_HOME/dbs/init${standby}.ora
	export ORACLE_SID=$standby
	\sqlplus sys/Oracle12 as sysdba<<XXX
	startup nomount
	XXX
	exit
EOS
}

function run_duplicate
{
	info "Lance la duplication..."
	cat<<EOR >/tmp/duplicate.rman
	run {
		allocate channel prmy1 type disk;
		allocate channel prmy2 type disk;
		allocate auxiliary channel stby1 type disk;
		allocate auxiliary channel stby2 type disk;
		duplicate target database for standby from active database
		spfile
			parameter_value_convert '$primary','$standby'
			set db_unique_name='$standby'
			set control_files='+DATA','+FRA'
			set cluster_database='false'
			set db_file_name_convert='+DATA/$standby/','+DATA/$primary/','+FRA/$standby/','+FRA/$primary/'
			set log_file_name_convert='+DATA/$standby/','+DATA/$primary/','+FRA/$standby/','+FRA/$primary/'
			set fal_server='$primary'
			set standby_file_management='AUTO'
			set log_archive_config='dg_config=($primary,$standby)'
			set log_archive_dest_1='location=USE_DB_RECOVERY_FILE_DEST valid_for=(all_logfiles,all_roles) db_unique_name=$standby'
			set log_Archive_dest_2='service=$primary async noaffirm reopen=15 valid_for=(all_logfiles,primary_role) db_unique_name=$primary'
			nofilenamecheck
		 ;
	}
EOR

	exec_cmd "rman target sys/$oracle_password@$primary auxiliary sys/$oracle_password@$standby @/tmp/duplicate.rman"
}

function duplicate
{
	if [ $skip_configuration == no ]
	then
		if [ $skip_setup_primary == no ]
		then
			line_separator
			info "Setup primary database $primary"
			run_sqlplus "$(set_primary_cfg)"
			LN

			line_separator
			add_standby_redolog
		fi

		line_separator
		setup_tnsnames

		line_separator
		primary_listener_add_static_entry

		line_separator
		standby_listener_add_static_entry
	fi

	line_separator
	start_standby

	line_separator
	run_duplicate
}

function cmd_setup_broker_for_database
{
	typeset -r db=$1

	to_exec "alter system set dg_broker_start=false scope=both sid='*';"
	to_exec "alter system reset dg_broker_config_file1 scope=spfile sid='*';"
	to_exec "alter system reset dg_broker_config_file2 scope=spfile sid='*';"

	to_exec "alter system set dg_broker_config_file1 = '+DATA/$db/dr1db_$db.dat' scope=both sid='*';"
	to_exec "alter system set dg_broker_config_file2 = '+DATA/$db/dr2db_$db.dat' scope=both sid='*';"

	to_exec "alter system set dg_broker_start=true scope=both sid='*';"
}

typeset	-r	primary_host=$(hostname -s)
typeset	-r	tnsnames_file=$TNS_ADMIN/tnsnames.ora

info "Create dataguard :"
info "	- from database $primary on $primary_host"
info "	- with database $standby on $standby_host"
LN

line_separator
info -n "Try to join $standby_host : "
ping -c 1 $standby_host >/dev/null 2>&1
if [ $? -eq 0 ]
then
	info -f "[$OK]"
	LN
else
	info -f "[$KO]"
	exit 1
fi

line_separator
info "Load env for $primary"
ORACLE_SID=$primary
ORAENV_ASK=NO . oraenv
LN

[ $skip_duplicate == no ] && duplicate

line_separator
info "Il faut redémarrer la base pour prendre en compte log_archive_dest_2 (bug ?)"
exec_cmd "srvctl stop database -db $primary"
exec_cmd "srvctl start database -db $primary"
LN

info "Enregistre la base dans le CRS."
exec_cmd "ssh -t oracle@$standby_host \". .profile; srvctl add database \
	-db $standby \
	-oraclehome $ORACLE_HOME \
	-spfile $ORACLE_HOME/dbs/spfile${standby}.ora \
	-role physical_standby \
	-dbname $primary \
	-diskgroup DATA,FRA \
	-verbose\""
LN

info "Stop la base"
run_sqlplus_on_standby "$(to_exec "shutdown immediate;")"
LN

info "Démarre la base"
exec_cmd "ssh -t oracle@$standby_host \". .profile; srvctl start database -db $standby\""
LN

line_separator
#alter database recover managed standby database cancel;
info "Démarre la synchro."
#	alter database recover managed standby database using current logfile disconnect;
#	est deprecated. Voir alert.log après exécution.
run_sqlplus_on_standby "$(to_exec "alter database recover managed standby database disconnect;")"
LN

line_separator
info "Configuration du broker sur les bases :"
info "  Sur la primaire $primary"
run_sqlplus "$(cmd_setup_broker_for_database $primary)"
LN
info "  Sur la standby $standby"
run_sqlplus_on_standby "$(cmd_setup_broker_for_database $standby)"
LN

info -n "Temporisation : "; pause_in_secs 10; LN

line_separator
info "Activation du broker"
run_sqlplus "$(to_exec "alter system set log_Archive_dest_2='';")"
run_sqlplus_on_standby "$(to_exec "alter system set log_Archive_dest_2='';")"
LN
dgmgrl<<EOS 
connect sys/$oracle_password
create configuration 'PRODCONF' as primary database is $primary connect identifier is $primary; 
add database $standby as connect identifier is $standby maintained as physical;
enable configuration;
EOS
LN

line_separator
info "Maintenant les services :("
info "Plus tard..."