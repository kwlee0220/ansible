#!  /bin/bash

ansible-playbook -i mdt/inventory base/ssh_connection.yml -K
ansible -i mdt/inventory mdt -m ping
