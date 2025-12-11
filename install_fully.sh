#!  /bin/bash

ansible-playbook -i hosts playbooks/linux/apt_update_upgrade.yml -K
ansible-playbook -i hosts install_basic_apps.yml -K
ansible-playbook -i hosts install_development.yml -K
ansible-playbook -i hosts install_gui.yml -K
ansible-playbook -i hosts playbooks/mdt/install_mdt_infra.yml -K