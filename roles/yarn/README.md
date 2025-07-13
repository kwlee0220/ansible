# Yarn Role

이 Ansible role은 Yarn 패키지 매니저를 설치하고 구성하는 역할을 담당합니다.

## 기능

- Node.js 및 npm을 통한 Yarn 설치
- Corepack을 통한 Yarn 설치 (Node.js 16.10+)
- 공식 저장소를 통한 Yarn 설치
- Yarn 설정 구성
- 전역 패키지 관리 설정
- 성능 및 보안 최적화

## 요구사항

- Ubuntu/Debian 기반 시스템
- Ansible 2.9+
- nodejs role (npm/corepack 방법 사용 시 자동으로 포함됨)

## 설치 방법

이 role은 3가지 설치 방법을 지원합니다:

### 1. npm을 통한 설치 (기본)
```yaml
yarn_install_method: "npm"
```

### 2. Corepack을 통한 설치 (Node.js 16.10+)
```yaml
yarn_install_method: "corepack"
```

### 3. 공식 저장소를 통한 설치
```yaml
yarn_install_method: "repository"
```

## 변수

### 기본 변수 (defaults/main.yml)

| 변수명 | 기본값 | 설명 |
|--------|--------|------|
| `yarn_install_method` | "npm" | 설치 방법 (npm, corepack, repository) |
| `yarn_version` | "latest" | Yarn 버전 |
| `yarn_install_global` | true | 전역 설치 여부 |
| `yarn_config_registry` | "https://registry.yarnpkg.com" | 패키지 레지스트리 |
| `yarn_config_cache_folder` | "~/.cache/yarn" | 캐시 폴더 |
| `yarn_config_global_folder` | "~/.yarn/global" | 전역 패키지 폴더 |
| `yarn_network_timeout` | 100000 | 네트워크 타임아웃 (밀리초) |
| `yarn_network_concurrency` | 8 | 동시 네트워크 연결 수 |
| `yarn_enable_telemetry` | false | 텔레메트리 활성화 |
| `yarn_enable_scripts` | true | 스크립트 실행 허용 |

## 사용법

### 기본 설치

```yaml
- hosts: all
  roles:
    - yarn
```

### 사용자 정의 설정

```yaml
- hosts: all
  vars:
    yarn_install_method: "corepack"
    yarn_version: "1.22.19"
    yarn_config_registry: "https://registry.npmjs.org/"
    yarn_enable_telemetry: false
  roles:
    - yarn
```

### 특정 버전 설치

```yaml
- hosts: all
  vars:
    yarn_version: "1.22.19"
  roles:
    - yarn
```

## 설치된 구성 요소

- Yarn 패키지 매니저
- Yarn 설정 파일
- 전역 패키지 디렉토리
- 캐시 디렉토리
- PATH 환경 변수 설정

## Yarn 명령어

### 기본 명령어
```bash
# 버전 확인
yarn --version

# 새 프로젝트 초기화
yarn init

# 패키지 설치
yarn add [package-name]

# 개발 의존성 설치
yarn add --dev [package-name]

# 의존성 설치
yarn install

# 전역 패키지 설치
yarn global add [package-name]

# 패키지 제거
yarn remove [package-name]

# 스크립트 실행
yarn [script-name]
```

### 설정 관리
```bash
# 현재 설정 확인
yarn config list

# 특정 설정 확인
yarn config get registry

# 설정 변경
yarn config set registry https://registry.npmjs.org/

# 설정 삭제
yarn config delete registry
```

## 성능 최적화

### 캐시 설정
```bash
# 캐시 폴더 확인
yarn config get cache-folder

# 캐시 폴더 변경
yarn config set cache-folder /path/to/cache
```

### 네트워크 설정
```bash
# 네트워크 타임아웃 설정
yarn config set network-timeout 300000

# 동시 연결 수 설정
yarn config set network-concurrency 16
```

## 보안 고려사항

### 1. 레지스트리 검증
공식 레지스트리 사용을 권장합니다:
```bash
yarn config set registry https://registry.yarnpkg.com/
```

### 2. 스크립트 실행 제어
신뢰할 수 없는 패키지의 스크립트 실행을 제한:
```bash
yarn config set enableScripts false
```

### 3. 텔레메트리 비활성화
```bash
yarn config set enableTelemetry false
```

## 문제 해결

### 권한 문제
```bash
# 전역 패키지 설치 시 권한 오류
sudo yarn global add [package-name]

# 또는 사용자 디렉토리에 설치
yarn config set prefix ~/.yarn
```

### 캐시 문제
```bash
# 캐시 정리
yarn cache clean

# 캐시 폴더 확인
yarn cache dir
```

### 네트워크 문제
```bash
# 프록시 설정
yarn config set proxy http://proxy-server:port
yarn config set https-proxy http://proxy-server:port

# 타임아웃 증가
yarn config set network-timeout 300000
```

### 버전 충돌
```bash
# 설치된 Yarn 버전 확인
yarn --version

# 특정 버전으로 변경
yarn policies set-version 1.22.19
```

## npm과의 차이점

| 기능 | Yarn | npm |
|------|------|-----|
| 설치 속도 | 빠름 (병렬 설치) | 상대적으로 느림 |
| 보안 | yarn.lock으로 일관성 보장 | package-lock.json |
| 오프라인 모드 | 지원 | 제한적 |
| 플러그인 | 제한적 | 풍부한 생태계 |
| 명령어 | yarn add | npm install |

## 의존성

- nodejs role (npm/corepack 방법 사용 시)
- curl, gnupg (repository 방법 사용 시)
- systemd 지원 시스템

## 참고 자료

- [Yarn 공식 문서](https://yarnpkg.com/getting-started)
- [Yarn 설정 가이드](https://yarnpkg.com/configuration)
- [npm vs Yarn 비교](https://yarnpkg.com/advanced/qa#why-should-you-use-yarn) 