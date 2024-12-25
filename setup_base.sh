#!  /bin/bash

sudo apt update && sudo apt upgrade -y

sudo apt install openssh-server -y
mkdir ~/.ssh
ssh-keygen -t rsa -f ~/.ssh/id_rsa -N '' -q

# VirtualBox Guest Additions 설치
# sudo apt install virtualbox-guest-utils virtualbox-guest-x11 -y
