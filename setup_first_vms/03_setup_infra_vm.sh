#!/bin/bash
# vim: ts=4:sw=4

. ~/plescripts/plelib.sh
. ~/plescripts/networklib.sh
. ~/plescripts/global.cfg
EXEC_CMD_ACTION=EXEC

typeset -r ME=$0

typeset -r str_usage=\
"Usage : $ME
Doit être exécuté sur le serveur d'infrastructure : $infra_hostname
"

script_banner $ME $*

must_be_executed_on_server "$infra_hostname"

line_separator
#	Le serveur sert de gateway sur internet.
exec_cmd "sysctl -w net.ipv4.ip_forward=1"
exec_cmd "echo \"net.ipv4.ip_forward = 1\" >> /etc/sysctl.d/ip_forward.conf"
typeset	-r network=$(right_pad_ip $infra_network)
exec_cmd "firewall-cmd --permanent --direct --passthrough ipv4 -t nat -I POSTROUTING -o $if_net_name -j MASQUERADE -s $network/$if_net_prefix"
exec_cmd "firewall-cmd --reload"
LN

line_separator
info "Enable & start NFS services"
exec_cmd "systemctl enable rpcbind"
exec_cmd "systemctl start rpcbind"
LN

exec_cmd "systemctl enable nfs-server"
exec_cmd "systemctl start nfs-server"
LN

info "Add NFS to trusted zone"
exec_cmd "firewall-cmd --add-service=nfs --permanent --zone=trusted"
exec_cmd "firewall-cmd --reload"
LN

line_separator
exec_cmd "echo \"$client_hostname:/home/$common_user_name/plescripts /mnt/plescripts nfs rw,$nfs_options,comment=systemd.automount\"  >> /etc/fstab"
LN

line_separator
info "Create VG asm01 on first unused disk :"
exec_cmd "~/plescripts/san/create_vg.sh -device=auto -vg=asm01"
LN

line_separator
info "Setup SAN"
exec_cmd "~/plescripts/san/targetcli_default_cfg.sh"
LN

case $ntp_tool in
	chrony)
		exec_cmd ~/plescripts/ntp/configure_chrony.sh -role=infra
		;;

	ntp)
		exec_cmd ~/plescripts/ntp/configure_ntp.sh -role=infra
		;;
esac

exec_cmd ~/plescripts/gadgets/customize_logon.sh -name=$infra_hostname

line_separator
info "Configure DNS"
exec_cmd "~/plescripts/dns/install/01_install_bind.sh"
exec_cmd "~/plescripts/dns/install/03_configure.sh"

exec_cmd ~/plescripts/dns/add_server_2_dns.sh	-name=$client_hostname		\
												-ip_node=1

exec_cmd ~/plescripts/dns/add_server_2_dns.sh	-name=$master_hostname		\
												-ip_node=$master_ip_node

exec_cmd ~/plescripts/dns/show_dns.sh
LN

exec_cmd ~/plescripts/nm_workaround/create_service.sh -role=infra
LN

exec_cmd ~/plescripts/shell/set_plymouth_them
LN
