#!  /bin/bash

# Ansible 설치
sudo apt update && sudo apt upgrade -y
sudo apt-add-repository ppa:ansible/ansible
sudo apt update && sudo apt upgrade -y
sudo apt install ansible -y
sudo apt install python3-pip git -y
sudo pip3 install git+https://github.com/larsks/ansible-toolbox

sudo apt install openssh-server -y
mkdir ~/.ssh
ssh-keygen -t rsa -f ~/.ssh/id_rsa -N '' -q

# VirtualBox Guest Additions 설치
# sudo apt install virtualbox-guest-utils virtualbox-guest-x11 -y