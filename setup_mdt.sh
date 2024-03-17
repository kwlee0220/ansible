#!  /bin/bash

ansible-playbook -i mdt/inventory base/ssh_connection.yml -K
ansible-role -i mdt/inventory ntp --hosts mdt
ansible -i mdt/inventory mdt -m command -a date
