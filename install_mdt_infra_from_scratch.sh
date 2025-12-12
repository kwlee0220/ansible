#!  /bin/bash

ansible-playbook -i hosts \
  install_basic_apps.yml \
  install_development.yml \
  install_gui.yml \
  playbooks/mdt/install_mdt_infra.yml \
  -K