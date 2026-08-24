# nvidia_driver

Ubuntu 공식 저장소(restricted)의 NVIDIA 드라이버를 원하는 브랜치로 올린다.
PPA(`ppa:graphics-drivers`)나 NVIDIA `.run` 설치 파일은 쓰지 않는다.

## 왜 저장소 패키지만 쓰는가

**Secure Boot** 때문이다. 커널은 서명되지 않은 모듈의 로드를 거부하는데,

| 설치 경로 | 커널 모듈 | Secure Boot |
| --- | --- | --- |
| `linux-modules-nvidia-*` (저장소) | Canonical 이 **미리 빌드하고 서명** | 그대로 동작 |
| `nvidia-dkms-*` (DKMS) | 설치 시점에 로컬 빌드, 서명 없음 | MOK 키를 직접 만들어 등록해야 함 |
| NVIDIA `.run` | 로컬 빌드, 서명 없음 | 위와 같음 + apt 관리 밖 |

문제는 `apt install nvidia-driver-595` 만 실행하면 apt 가 의존성을 **DKMS 쪽으로 푼다**는 점이다.
`linux-modules-nvidia-595-<flavour>` 가 `nvidia-dkms-595` 를 `Provides` 하므로,
두 패키지를 **함께 지정**해야 사전 서명 모듈이 선택된다. 이 role 이 하는 일이 그것이다.

## 하는 일

1. **detect** — 커널 flavour(HWE / GA), Secure Boot 상태, 현재 실행 중인 드라이버 버전 파악
2. **validate** — GPU 존재 확인, 요청한 브랜치가 저장소에 있는지, 후보 버전이 최소 요구치를
   넘는지 확인. 그리고 **설치 시뮬레이션(`apt-get install -s`)에 `nvidia-dkms` 가 섞이면 중단**한다
   (재부팅 후에야 화면이 안 나오는 것으로 알게 되는 사고를 막는다)
3. **install** — 드라이버 + 사전 서명 커널 모듈 설치, 구 브랜치 잔여 패키지 정리,
   재부팅 필요 여부 보고(또는 직접 재부팅)
4. **prime** — (선택) `prime-select` 모드 변경

## 실행

```bash
# 기본 (595 브랜치, 재부팅은 직접)
ansible-playbook -i hosts_local playbooks/linux/upgrade_nvidia_driver.yml -K

# Isaac Sim 요구치를 함께 검사하고, PRIME 을 nvidia 로 고정
ansible-playbook -i hosts_local playbooks/linux/upgrade_nvidia_driver.yml -K \
  -e nvidia_driver_min_version=595.58.03 \
  -e nvidia_driver_prime_mode=nvidia
```

드라이버 교체는 **재부팅해야 적용된다.** 재부팅 전까지 `nvidia-smi` 는 예전 버전을
계속 보고하며, role 도 그 사실을 마지막에 알려준다.
원격 대상이라 role 이 직접 재부팅하게 하려면 `-e nvidia_driver_reboot=true` 를 준다.

## 주요 변수

| 변수 | 기본값 | 설명 |
| --- | --- | --- |
| `nvidia_driver_branch` | `"595"` | 설치할 브랜치. `ubuntu-drivers devices` 로 지원 목록 확인 |
| `nvidia_driver_open` | `false` | `-open`(open GPU kernel module) 변형 사용. Turing 이후 GPU 만 가능 |
| `nvidia_driver_use_prebuilt_modules` | `true` | 사전 서명 모듈 사용. Secure Boot 면 반드시 true |
| `nvidia_driver_assert_no_dkms` | `true` | 시뮬레이션에 DKMS 가 섞이면 실패 |
| `nvidia_driver_min_version` | `""` | 요구 최소 버전. 비우면 검사 안 함 |
| `nvidia_driver_reboot` | `false` | role 이 직접 재부팅할지 |
| `nvidia_driver_prime_mode` | `""` | `nvidia` / `on-demand` / `intel`. 비우면 건드리지 않음 |
| `nvidia_driver_autoremove` | `true` | 교체 후 구 브랜치 잔여 패키지 정리 |

## 커널 flavour 자동 판별

모듈 메타패키지 이름은 설치된 커널 계열에 따라 다르다.

- HWE 커널 (`linux-image-generic-hwe-22.04` 설치됨) → `linux-modules-nvidia-595-generic-hwe-22.04`
- GA 커널 → `linux-modules-nvidia-595-generic`

`detect.yml` 이 `dpkg-query` 로 확인해 알아서 고른다. flavour 메타패키지를 쓰므로
앞으로 커널이 올라가도 맞는 서명 모듈이 자동으로 따라온다.

## Isaac Sim 과의 관계

[isaac_sim](../isaac_sim/) role 은 드라이버를 설치하지 않고 버전만 검사한다
(`isaac_sim_required_driver_version`, 기본 `595.58.03`).
드라이버 업그레이드는 재부팅을 요구하므로 별도 role 로 떼어놨다. 순서는:

```bash
ansible-playbook -i hosts_local playbooks/linux/upgrade_nvidia_driver.yml -K \
  -e nvidia_driver_min_version=595.58.03 -e nvidia_driver_prime_mode=nvidia
sudo reboot
ansible-playbook -i hosts_local playbooks/rdfp/install_isaac_sim.yml -K
```

`prime-select` 가 `on-demand` 인 하이브리드(내장 GPU + NVIDIA) 구성에서는
Omniverse Kit 이 NVIDIA GPU 를 못 잡는 경우가 있어 `nvidia` 로 고정하는 편이 확실하다.
