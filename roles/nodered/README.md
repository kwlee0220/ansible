# Node-RED Role

이 Ansible role은 Node-RED를 설치하고 구성하는 역할을 담당합니다.

## 기능

- Node.js 및 npm을 통한 Node-RED 설치
- 전용 사용자 및 그룹 생성
- systemd 서비스 설정
- 보안 설정 (관리자 인증)
- 로그 설정
- 자동 시작 설정

## 요구사항

- Ubuntu/Debian 기반 시스템
- Ansible 2.9+
- nodejs role (자동으로 포함됨)

## 변수

### 기본 변수 (defaults/main.yml)

| 변수명 | 기본값 | 설명 |
|--------|--------|------|
| `nodered_install_method` | "npm" | 설치 방법 (npm 또는 systemd) |
| `nodered_version` | "latest" | Node-RED 버전 |
| `nodered_user` | "nodered" | Node-RED 실행 사용자 |
| `nodered_group` | "nodered" | Node-RED 실행 그룹 |
| `nodered_home` | "/home/nodered" | Node-RED 홈 디렉토리 |
| `nodered_port` | 1880 | 웹 인터페이스 포트 |
| `nodered_data_dir` | "/home/nodered/.node-red" | 데이터 디렉토리 |
| `nodered_service_enabled` | true | 서비스 자동 시작 |
| `nodered_service_started` | true | 서비스 시작 |
| `nodered_admin_auth` | false | 관리자 인증 활성화 |
| `nodered_admin_user` | "admin" | 관리자 사용자명 |
| `nodered_admin_password` | "" | 관리자 비밀번호 |
| `nodered_install_global` | true | 전역 설치 |
| `nodered_auto_start` | true | 시스템 부팅 시 자동 시작 |
| `nodered_flow_file` | "flows.json" | 플로우 파일명 |

## 사용법

### 기본 설치

```yaml
- hosts: all
  roles:
    - nodered
```

### 사용자 정의 설정

```yaml
- hosts: all
  vars:
    nodered_port: 8080
    nodered_admin_auth: true
    nodered_admin_user: "myadmin"
    nodered_admin_password: "mypassword"
    nodered_version: "3.1.0"
  roles:
    - nodered
```

## 설치된 구성 요소

- Node-RED (npm을 통한 전역 설치)
- PM2 (프로세스 관리자)
- node-red-admin (명령줄 도구)
- systemd 서비스
- 전용 사용자 및 그룹
- 로그 디렉토리

## 서비스 관리

```bash
# 서비스 상태 확인
sudo systemctl status nodered

# 서비스 시작
sudo systemctl start nodered

# 서비스 중지
sudo systemctl stop nodered

# 서비스 재시작
sudo systemctl restart nodered

# 로그 확인
sudo journalctl -u nodered -f
```

## 접속 정보

설치 완료 후 다음 주소로 접속할 수 있습니다:
- http://localhost:1880 (기본 포트)
- http://서버IP:1880 (원격 접속)

## 보안 고려사항

1. **관리자 인증 활성화**: `nodered_admin_auth: true`로 설정
2. **강력한 비밀번호 사용**: `nodered_admin_password` 설정
3. **방화벽 설정**: 필요한 포트만 열기
4. **HTTPS 설정**: 프로덕션 환경에서는 SSL/TLS 사용 권장

## 문제 해결

### 포트 충돌
다른 서비스가 1880 포트를 사용하는 경우 `nodered_port` 변수를 변경하세요.

### 권한 문제
Node-RED 사용자가 필요한 디렉토리에 대한 쓰기 권한을 가지고 있는지 확인하세요.

### 메모리 부족
`NODE_OPTIONS=--max_old_space_size=512` 환경 변수가 설정되어 있습니다. 필요에 따라 조정하세요.

## 의존성

- nodejs role (자동으로 포함됨)
- systemd 지원 시스템
- curl, gnupg 패키지 