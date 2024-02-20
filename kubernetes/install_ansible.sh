#!  /bin/bash

ansible-playbook base/ssh_connection.yml --limit k8s -K
ansible k8s -m ping
ansible-role sudo --hosts k8s -K

ansible-playbook kubernetes/main.yml