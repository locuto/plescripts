#!/bin/bash
# vim: ts=4:sw=4

. ~/plescripts/plelib.sh
. ~/plescripts/global.cfg
EXEC_CMD_ACTION=EXEC

typeset -r ME=$0
typeset -r str_usage=\
"Usage : $ME
	-vm_name=name     VM name
	-disk_name=name   Vbox disk name
	-os_device=nam    OS disk name like /dev/sdz

Add raw disk to SATA controller on the first free port, the controller must exists.
"

script_banner $ME $*

typeset		vm_name=undef
typeset		disk_name=undef
typeset		os_device=undef

while [ $# -ne 0 ]
do
	case $1 in
		-emul)
			EXEC_CMD_ACTION=NOP
			shift
			;;

		-vm_name=*)
			vm_name=${1##*=}
			shift
			;;

		-disk_name=*)
			disk_name=${1##*=}
			shift
			;;

		-os_device=*)
			os_device=${1##*=}
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

exit_if_param_undef vm_name		"$str_usage"
exit_if_param_undef disk_name	"$str_usage"
exit_if_param_undef os_device	"$str_usage"

function get_free_SATA_port
{
	VBoxManage showvminfo $vm_name > /tmp/${vm_name}.info
	typeset -ri nu=$(grep -E "^SATA"  /tmp/${vm_name}.info | sed "s/SATA (\([0-9]*\),.*/\1/" | tail -1)
	rm -f /tmp/${vm_name}.info
	echo $(( nu+1 ))
}

typeset	-r	disk_full_path="$vm_path/$vm_name/${disk_name}.vmdk"
typeset -r	on_port=$(get_free_SATA_port)

if [ ! -b $os_device ]
then
	error "Device $os_device not exists."
	LN
	exit 1
fi

typeset -r device_group=$(ls -l "$os_device" | cut -d\  -f4)

info "$os_device in group : $device_group"
info -n "$common_user_name member of group : $device_group "
if id|grep -q $device_group
then
	info -f "[$OK]"
	LN
else
	info -f "[$KO]"
	LN
	exit 1
fi

info "Create vmdk image"
exec_cmd VBoxManage	internalcommands createrawvmdk		\
						-filename \"$disk_full_path\"	\
						-rawdisk "$os_device"
LN

info "Attach vmdk image to $vm_name on port $on_port"
exec_cmd VBoxManage storageattach $vm_name				\
						--storagectl SATA				\
						--port $on_port					\
						--device 0						\
						--type hdd						\
						--mtype writethrough			\
						--medium \"$disk_full_path\"
LN
