#!  /bin/bash

sudo apt-add-repository ppa:ansible/ansible
sudo apt update && sudo apt upgrade -y
sudo apt install ansible -y