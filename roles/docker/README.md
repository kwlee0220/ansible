# Docker Role

이 Ansible role은 Ubuntu/Debian 시스템에 Docker CE와 Docker Compose를 설치합니다.

## 요구사항

- Ubuntu 20.04 LTS (Focal) 이상 또는 Debian 11 (Bullseye) 이상
- Ansible 2.9 이상
- sudo 권한

## 특징

- ✅ 최신 GPG 키 관리 방식 사용 (`/etc/apt/keyrings/` 디렉토리)
- ✅ `apt-key` deprecated 경고 해결
- ✅ Ubuntu와 Debian 모두 지원
- ✅ 시스템 아키텍처 자동 감지
- ✅ 멱등성(idempotent) 보장
- ✅ 기존 충돌 저장소 파일 자동 정리

## Role 변수

### 기본 변수 (defaults/main.yml)

```yaml
# Docker user를 docker 그룹에 추가 (선택사항)
# docker_user: "{{ ansible_user }}"

# Docker Compose 독립 실행형 설치를 위한 버전
docker_compose_version: "v2.24.5"

# Docker Compose 독립 실행형 바이너리 설치 여부
# (Docker CE와 함께 Docker Compose 플러그인이 기본으로 설치됨)
docker_compose_standalone: false

# Docker 서비스 설정
docker_service_enabled: true
docker_service_state: started
```

## 설치되는 패키지

- Docker CE (docker-ce)
- Docker CE CLI (docker-ce-cli)
- containerd.io
- Docker Buildx Plugin
- Docker Compose Plugin

## 사용법

### 기본 사용법

```yaml
---
- name: Install Docker
  hosts: all
  become: yes
  roles:
    - docker
```

### 사용자를 docker 그룹에 추가

```yaml
---
- name: Install Docker with user setup
  hosts: all
  become: yes
  vars:
    docker_user: "{{ ansible_user }}"
  roles:
    - docker
```

### Docker Compose 독립 실행형 설치

```yaml
---
- name: Install Docker with standalone Docker Compose
  hosts: all
  become: yes
  vars:
    docker_compose_standalone: true
    docker_compose_version: "v2.24.5"
  roles:
    - docker
```

## 예제 플레이북

프로젝트 루트에 있는 `install_docker.yml` 파일을 참조하세요:

```bash
ansible-playbook -i hosts install_docker.yml
```

## 설치 후 확인

Role 실행 후 다음 명령어로 설치를 확인할 수 있습니다:

```bash
# Docker 버전 확인
docker --version

# Docker Compose 버전 확인
docker compose version

# Docker 서비스 상태 확인
sudo systemctl status docker

# Docker 테스트 (사용자가 docker 그룹에 추가된 경우)
docker run hello-world
```

## 주요 개선사항

### v2.1 업데이트
- **충돌 저장소 정리**: 기존 Docker 저장소 파일들 자동 제거
- **안정성 향상**: "Conflicting values set for option Signed-By" 오류 방지

### v2.0 업데이트
- **deprecated `apt-key` 해결**: 최신 방식인 `/etc/apt/keyrings/` 디렉토리 사용
- **멀티 배포판 지원**: Ubuntu와 Debian 모두 지원
- **아키텍처 자동 감지**: amd64, arm64 등 자동 감지
- **멱등성 개선**: 키가 이미 존재하는 경우 스킵
- **경고 메시지 제거**: apt-key deprecated 경고 완전 해결

## 주의사항

- 사용자를 docker 그룹에 추가한 경우, sudo 없이 Docker를 사용하려면 로그아웃 후 다시 로그인하거나 `newgrp docker` 명령을 실행해야 합니다.
- Docker Compose는 기본적으로 플러그인으로 설치되므로 `docker compose` 명령을 사용합니다.
- 독립 실행형 Docker Compose를 설치한 경우 `docker-compose` 명령도 사용할 수 있습니다.

## 트러블슈팅

### 저장소 충돌 문제
"Conflicting values set for option Signed-By" 오류가 발생하는 경우:
```bash
# 수동으로 충돌하는 파일들 제거
sudo rm -f /etc/apt/sources.list.d/download_docker_com_linux_ubuntu.list
sudo rm -f /etc/apt/sources.list.d/docker-ce.list
sudo apt update
```
**참고**: 이 role은 자동으로 충돌하는 파일들을 정리합니다.

### GPG 키 관련 문제
이전에 `apt-key`로 설치된 키가 있는 경우:
```bash
# 기존 키 제거 (선택사항)
sudo apt-key del 9DC858229FC7DD38854AE2D88D81803C0EBFCD88
```

### 권한 문제
Docker 그룹 추가 후에도 권한 오류가 발생하는 경우:
```bash
# 현재 세션에서 그룹 변경 적용
newgrp docker
# 또는 로그아웃 후 다시 로그인
```

## 라이선스

MIT

## 작성자

Ansible User 