#!  /bin/bash

ansible-playbook desktop/generate_ssh_key.yml
ansible-playbook base/allow_sudoer.yml
ansible-playbook base/ssh_connection.yml