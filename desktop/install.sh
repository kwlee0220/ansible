#!  /bin/bash

sudo apt-add-repository ppa:ansible/ansible -y
sudo apt install ansible -y
sudo apt install git -y

ansible-pull -U https://github.com/kwlee0220/ansible_desktop.git
source ~/.bashrc

# Gradle Installation
sdk install gradle 7.6.3

conda activate
pip install --upgrade pip
pip install gdown
ansible-pull -U https://github.com/kwlee0220/ansible_desktop.git install_jdk8_oracle.yml
