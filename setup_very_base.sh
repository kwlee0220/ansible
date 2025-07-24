#! /bin/bash

# 처음 시작은 'root' 계정에서 시작하는 것을 가정

# apt database 초기화
apt update && sudo apt upgrade -y

# sudo 명령이 없는 경우에 'sudo' 패키지 설치
apt install sudo

# 사용자 계정 생성 (mdt)
useradd -m -s /bin/bash -G sudo mdt
# passwd mdt
echo 'mdt:mdt2025' | chpasswd
su mdt