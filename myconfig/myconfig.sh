#!/bin/bash
# vim: ts=4:sw=4

. ~/plescripts/plelib.sh
. ~/plescripts/global.cfg
EXEC_CMD_ACTION=EXEC

typeset -r ME=$0
typeset -r str_usage="Usage : $ME -apply [-skip_vim]|-backup [-emul]"

typeset	action=undef
typeset	install_gvim=yes

while [ $# -ne 0 ]
do
	case $1 in
		-emul)
			EXEC_CMD_ACTION=NOP
			shift
			;;

		-backup)
			action=backup
			shift
			;;

		-apply)
			action=apply
			shift
			;;

		-skip_vim)
			install_gvim=no
			shift
			;;

		*)
			error "Arg '$1' invalid."
			LN
			info "$str_usage"
			exit 1
			;;
	esac
done

exit_if_param_invalid action "backup apply" "$str_usage"

function run_apply
{
	typeset	-r	sudo_config="$USER ALL=(root) NOPASSWD: ALL"

	line_separator
	info "Config sudo for user $USER"
	exec_cmd -c "sudo grep \"$sudo_config\" /etc/sudoers"
	if [ $? -eq 0 ]
	then
		info "sudo is already configured."
	else
		info "Backup /etc/sudoers"
		exec_cmd sudo cp /etc/sudoers /etc/sudoers.backup
		LN

		typeset -i ln=$(sudo grep -n "root ALL=(ALL) ALL" /etc/sudoers | cut -d: -f1)
		ln=ln+1
		exec_cmd "sudo sed -i \"${ln}i\\$sudo_config\" /etc/sudoers"
		LN

		exec_cmd -c "sudo visudo -c -f /etc/sudoers"
		if [ $? -ne 0 ]
		then
			info "Broken file copied to /tmp/sudoers.broken"
			exec_cmd "sudo cp /etc/sudoers.backup /tmp/sudoers.broken"
			LN

			info "Restore /etc/sudoers from backup"
			exec_cmd "sudo mv /etc/sudoers.backup /etc/sudoers"
			LN
		else
			LN
		fi
	fi

	line_separator
	exec_cmd "cat ~/plescripts/setup_first_vms/for_inputrc /etc/inputrc > new_inputrc"
	exec_cmd "sudo mv new_inputrc /etc/inputrc"
	LN

	line_separator
	info "Apply bashrc extensions :"
	exec_cmd cp bashrc_extensions ~/.bashrc_extensions
	exec_cmd "sed -i \"/^.*bashrc_extensions.*$/d\" ~/.bashrc"
	exec_cmd "echo \"[ -f ~/.bashrc_extensions ] && . ~/.bashrc_extensions || true\" >> ~/.bashrc"
	LN

	if [ $install_gvim == yes ]
	then
		line_separator
		typeset	gvim_installed=no
		. /etc/os-release
		case "$ID" in
			opensuse)
				exec_cmd -c "sudo zypper install git-core gvim"
				[ $? -eq 0 ] && gvim_installed=yes
				;;

			neon)
				exec_cmd "sudo apt install vim-gnome"
				[ $? -eq 0 ] && gvim_installed=yes
				;;

			*)
				warning "$PRETTY_NAME : installation de gvim non faite."
				;;
		esac
		LN

		if [ $gvim_installed == yes ]
		then
			line_separator
			info "[G]vim configuration :"
			exec_cmd "~/plescripts/myconfig/vim_config.sh -restore"
			LN
			exec_cmd "~/plescripts/myconfig/vim_plugin.sh -init"
			LN
		fi
	fi

	line_separator
	info "tmux configuration :"
	exec_cmd cp mytmux.conf ~/.tmux.conf
	LN

	line_separator
	exec_cmd -c "~/plescripts/shell/set_plescripts_acl.sh"
	LN
}

function run_backup
{
	line_separator
	info "Backup bashrc extensions :"
	exec_cmd cp ~/.bashrc_extensions ~/plescripts/myconfig/bashrc_extensions
	LN

	line_separator
	info "Backup [G]vim configuration :"
	exec_cmd "~/plescripts/myconfig/vim_config.sh -backup"
	LN

	line_separator
	info "tmux configuration :"
	exec_cmd cp ~/.tmux.conf ~/plescripts/myconfig/mytmux.conf
	LN
}

if [ $action == apply ]
then
	run_apply
else
	run_backup
fi
