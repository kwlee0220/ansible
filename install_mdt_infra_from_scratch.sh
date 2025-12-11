#!  /bin/bash

ansible-playbook -i hosts \
  playbooks/linux/apt_update_upgrade.yml \
  install_basic_apps.yml \
  install_development.yml \
  install_gui.yml \
  playbooks/mdt/install_mdt_infra.yml \
  -K