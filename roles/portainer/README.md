# portainer role

Docker 위에 Portainer CE를 설치하고 실행하는 role입니다.

## Requirements

- Docker Engine 이 사전에 설치되어 있어야 합니다.
- `community.docker` collection 이 필요합니다.

설치 예:

```bash
ansible-galaxy collection install community.docker