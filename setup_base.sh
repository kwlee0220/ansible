#!  /bin/bash

# Ansible 설치
sudo apt update && sudo apt upgrade -y
sudo apt-add-repository ppa:ansible/ansible
sudo apt update && sudo apt upgrade -y
sudo apt install ansible -y

# Git 설치
sudo apt install git -y

# 설치 모듈 clone
git clone 