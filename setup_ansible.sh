#!  /bin/bash

ansible-playbook desktop/generate_ssh_key.yml
ansible-playbook base/allow_sudoer.yml
ansible-playbook base/collect_ssh_pub_keys.yml
ansible-playbook base/deploy_ssh_pub_key.yml