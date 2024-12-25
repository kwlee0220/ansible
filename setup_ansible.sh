#!  /bin/bash

# Ansible 설치
sudo apt-add-repository ppa:ansible/ansible -y
sudo apt update
sudo apt install ansible -y

sudo apt install python3-pip git -y
sudo pip3 install git+https://github.com/larsks/ansible-toolbox
