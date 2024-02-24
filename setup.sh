#!  /bin/bash

ansible-playbook base/ssh_connection.yml --limit $1 -K
ansible $1 -m ping
