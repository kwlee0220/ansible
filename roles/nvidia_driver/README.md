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
3. **prime** — (선택) `prime-select` 모드 변경. 설치보다 **먼저** 한다 — 설정 파일만
   쓰므로 새 드라이버가 필요 없고, install 이 재부팅하는 경우 그 한 번으로 둘 다 적용된다
4. **install** — 드라이버 + 사전 서명 커널 모듈 설치, 구 브랜치 잔여 패키지 정리,
   재부팅 필요 여부 보고(또는 직접 재부팅 후 실제 로드 여부 검증)

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
| `nvidia_driver_autoremove` | `true` | 교체 후 남은 **NVIDIA 패키지만** 정리 (아래 참조) |

## 잔여 패키지 정리 범위

`nvidia_driver_autoremove` 는 `apt autoremove` 를 그대로 부르지 않는다.
전역 autoremove 는 드라이버와 무관한 고아 패키지까지 지우기 때문이다.
(실측: 이 저장소를 쓰는 머신에서 `ros-humble-hpp-fcl`, `libfwupd2` 등이 함께 지워졌다.)

대신 `apt-get -s autoremove` 로 후보를 뽑아 **이름에 nvidia 가 든 것만** 제거하고,
나머지는 지우지 않고 목록으로 알려준다.

```
TASK [Report unrelated orphans that were left alone]
  다음 패키지도 고아 상태지만 NVIDIA 와 무관하여 남겨두었다:
  libfwupdplugin5, libfwupd2, libgcab-1.0-0, slirp4netns, ...
  정리하려면 직접 `sudo apt autoremove` 를 실행할 것.
```

## 부분 실행과 dry-run

단계별 태그(`validate` / `prime` / `install`)로 나눠 실행할 수 있다.
`detect` 는 `always` 태그라 어느 경우에도 먼저 돈다 — 커널 flavour 를 여기서 정하기
때문에 이것 없이는 모듈 패키지 이름을 만들 수 없다.

```bash
ansible-playbook -i hosts_local playbooks/linux/upgrade_nvidia_driver.yml -K --tags install
```

`--check` 로 dry-run 하면 조회·시뮬레이션은 실제로 수행하고 설치만 건너뛴다.
설치가 일어나지 않았으므로 설치본 버전 확인과 재부팅 판정은 자동으로 생략된다.

```bash
ansible-playbook -i hosts_local playbooks/linux/upgrade_nvidia_driver.yml -K --check
```

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
