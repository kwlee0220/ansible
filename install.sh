#!  /bin/bash

# setup_ansible_base
ansible-playbook -i hosts install_basic_apps.yml install_development.yml install_gui.yml -K

# ansible-pull -U https://github.com/kwlee0220/ansible.git desktop/local.yml
# source ~/.bashrc

# # Gradle Installation
# sdk install gradle 5.6.4

# conda activate
# pip install --upgrade pip
# pip install gdown
# conda deactivate

# ansible-pull -U https://github.com/kwlee0220/ansible.git base/install_jdk8_oracle.yml -c local --limit 127.0.0.1
# ansible-pull -U https://github.com/kwlee0220/ansible.git base/install_docker.yml -c local --limit 127.0.0.1
# ansible-pull -U https://github.com/kwlee0220/ansible.git desktop/install_xrdp.yml
