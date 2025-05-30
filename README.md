## 새 컴퓨터에 ubuntu가 설치된 상태에서 ansible로 원격 install하는 과정
- 새 컴퓨터에서 apt를 update하고 upgrade 시키고 reboot 시킨다. (Ansible node)
    - ```sudo apt update && sudo apt upgrade -y && sudo shutdown -r now```
- 새 컴퓨터에 ssh-server를 설치해서 원격에서 ssh를 통해 접속되게 하도록 한다.
    - ```sudo apt install openssh-server -y```
- 새 컴퓨터에서 네트워크가 가능한지 확인하고, IP 주소를 확인한다.
    - ```ip a```
- 만일 ansible control 컴퓨터에 ssh key가 없는 경우에는 키를 생성한다.
    - ```ssh-keygen -t rsa -f ~/.ssh/id_rsa -N '' -q```
- Ansible control 컴퓨터의 ssh key를 새 컴퓨터에 배포하고, passwd 없이 ssh 접속 가능한지 확인한다.
    - ```ssh-copy-id <node-ip>```
- Ansible control 컴퓨터의 hosts 파일에 설치 대상 컴퓨터의 ip 주소를 추가한다.
    - 'hosts' 파일의 위치는 ansible script 설치 최상위 디렉토리를 권장함.
- 최신 Ansible을 설치한다.
    - ```sudo apt update```
    - ```sudo apt install software-properties-common```
    - ```sudo add-apt-repository --yes --update ppa:ansible/ansible```
    - ```sudo apt update```
    - ```sudo apt install ansible```
- Ansible control에서 ansible ping이 가능한지 확인한다.
    - ```ansible -i hosts all -m ping```
- Ansible control에서 ansible-playbook을 이용하여 basic apps을 설치한다.
    - ```ansible-playbook -i hosts install_basic_apps.yml -K```
- 설치가 완료되면 ssh로 ansible node (새 컴퓨터)에 접속하여 주요한 app들이 설치되었는지 확인한다.
    - fzf, gdu, htop, neofetch 등
- Ansible control에서 ansible-playbook을 이용하여 개발에 필요한 app들을 설치한다.
    - ```ansible-playbook -i hosts install_development.yml -K```
- 설치가 완료되면 ssh로 ansible node (새 컴퓨터)에 접속하여 주요한 app들이 설치되었는지 확인한다.
    ```
        sdk list
        java -version
        gradle -version
    ```
- Ansible control에서 ansible-playbook을 이용하여 GUI 관련 app (xrdp)들을 설치한다.
    - ```ansible-playbook -i hosts install_gui.yml -K```

### Local에서 설치하기 위해 ansible까지 설치하는 경우
```
setup_ansible.sh
```
### 특정 role만 실행하기
```
ansible-role <role>
```
### 특정 task만 실행하기
```
ansible-task <task-yml-file>
```

## Samba를 통해 디렉토리 공유하기
#### 1. 디렉토리를 공개할 호스트에서 samba를 설치한다.
```
ansible-playbook -i hosts samba/install_samba.yml -K
```
#### 2. 해당 호스트에 Samba client를 생성한다. (필요한 경우만)
```
ansible-playbook -i hosts samba/add_samba_user.yml -K
```
이때 samba client는 해당 linux 계정의 사용자 계정과 관계가 전혀 없고, 원격에서 samba를 통해 접속할 때만 사용하는 client이다.

#### 3. 해당 호스트의 특정 디렉토리를 공유로 설정한다.
```
ansible-playbook -i hosts samba/add_samba_share.yml -K
```
- 'Share name': Publish할 디렉토리에 부여할 식별자.
- 'Path to the share directory': 공개할 디렉토리 경로명.
- 'Samba client user id': 공개된 디렉토리에 접속할 samba client id.