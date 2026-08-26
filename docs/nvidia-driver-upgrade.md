# NVIDIA 드라이버 업그레이드 (Ubuntu 22.04 / Secure Boot)

Isaac Sim 설치를 위해 NVIDIA 드라이버를 올리면서 정리한 문서.
`ultra-p3` (Ubuntu 22.04.5, RTX 4000 SFF Ada) 기준으로 실측한 값이 들어있다. (2026-08-24)

**결론부터:**

```bash
sudo apt update
sudo apt install linux-modules-nvidia-595-generic-hwe-22.04 nvidia-driver-595
sudo reboot
```

`nvidia-driver-595` **하나만** 설치하면 안 된다. 이유는 [3장](#3-함정-드라이버-패키지만-설치하면-dkms-로-빠진다).

---

## 1. 현재 상태 진단

무엇을 설치할지 정하기 전에 네 가지를 확인한다.

```bash
# GPU 모델과 실행 중인 드라이버
nvidia-smi

# 커널 모듈을 어떤 방식으로 쓰고 있는지 (DKMS vs 사전 빌드)
dpkg -l | grep -E "nvidia|linux-modules-nvidia"

# Secure Boot 상태  ← 설치 방법을 결정하는 가장 중요한 항목
mokutil --sb-state

# 저장소에 어떤 브랜치가 있고, 이 GPU 에 뭐가 맞는지
apt-cache search --names-only '^nvidia-driver-[0-9]+$'
ubuntu-drivers devices
```

`ultra-p3` 의 결과:

| 항목 | 값 |
| --- | --- |
| GPU | RTX 4000 SFF Ada (20GB) — Ada 세대라 RT 코어 있음 → Isaac Sim 지원 대상 |
| 실행 중 드라이버 | **580.173.02** (`jammy-updates/restricted`) |
| 커널 모듈 방식 | `linux-modules-nvidia-580-generic-hwe-22.04` = **사전 빌드 + 서명** (DKMS 아님) |
| Secure Boot | **enabled** |
| 커널 | 6.8.0-138-generic (HWE) |
| 저장소 후보 | `nvidia-driver-595` → **595.84**, `nvidia-driver-610` → 610.43.02 |
| PRIME | `on-demand` (Intel 내장 GPU + NVIDIA 하이브리드) |

Isaac Sim 6.0.x 요구치가 **595.58.03 이상**이므로 595.84 면 충족한다.

> PPA(`ppa:graphics-drivers`)나 NVIDIA `.run` 파일이 필요할 것 같지만, 22.04 저장소에 이미 595 / 610 이 들어와 있다. 추가 저장소를 붙일 이유가 없다.

---

## 2. 왜 저장소 패키지만 쓰는가 — Secure Boot

Secure Boot 가 켜진 커널은 **서명되지 않은 모듈의 로드를 거부한다.** 설치 경로마다 커널 모듈이 어디서 오는지가 다르다.

| 설치 경로 | 커널 모듈 | Secure Boot 에서 |
| --- | --- | --- |
| `linux-modules-nvidia-*` (Ubuntu 저장소) | Canonical 이 **미리 빌드하고 서명** | 그대로 동작 |
| `nvidia-dkms-*` (DKMS) | 설치 시점에 **로컬 빌드**, 서명 없음 | 로드 거부 → MOK 키 직접 등록 필요 |
| NVIDIA `.run` 설치 파일 | 로컬 빌드, 서명 없음 | 위와 같음 + apt 관리 밖으로 벗어남 |

DKMS 나 `.run` 을 쓰려면 MOK(Machine Owner Key)를 만들어 등록해야 하는데, **재부팅 시 파란 화면에서 수동으로 조작**해야 하는 절차라 원격/자동화와 상성이 나쁘다. 게다가 커널이 올라갈 때마다 다시 빌드된다.

지금 580 이 문제없이 도는 이유가 바로 사전 서명 모듈을 쓰고 있기 때문이다. **그 구조를 그대로 유지한 채 브랜치만 올리는 것**이 이 문서의 목표다.

---

## 3. 함정: 드라이버 패키지만 설치하면 DKMS 로 빠진다

`sudo apt install nvidia-driver-595` 만 실행하면 apt 가 의존성을 **DKMS 쪽으로 푼다.** 실제 시뮬레이션 결과:

```console
$ apt-get install -s nvidia-driver-595 | grep -E "^Inst (dkms|nvidia-dkms)"
Inst dkms (2.8.7-2ubuntu2.2 ...)
Inst nvidia-dkms-595 (595.84-0ubuntu0.22.04.1 ...)
```

Secure Boot 가 켜진 상태에서 이대로 진행하면 **재부팅 후에야** 문제를 알게 된다. 화면이 안 뜨거나 내장 GPU 로 떨어지고, `nvidia-smi` 는 `NVIDIA-SMI has failed because it couldn't communicate with the NVIDIA driver` 를 뱉는다.

이유는 패키지 관계에 있다. 커널 모듈 메타패키지가 DKMS 패키지를 대신 만족시킨다:

```console
$ apt-cache show linux-modules-nvidia-595-generic-hwe-22.04 | grep Provides
Provides: nvidia-dkms-595 (= 595.84-0ubuntu0.22.04.1), nvidia-prebuilt-kernel
```

즉 `nvidia-dkms-595` 를 만족시키는 후보가 둘인데, 아무것도 지정하지 않으면 apt 가 실제 DKMS 패키지를 고른다. **두 패키지를 함께 지정하면** 사전 빌드 쪽이 선택된다.

```console
$ apt-get install -s linux-modules-nvidia-595-generic-hwe-22.04 nvidia-driver-595 \
    | grep -E "^Inst (dkms|nvidia-dkms)"
(출력 없음)
```

이것이 아래 명령에 패키지가 두 개 들어가는 이유다.

---

## 4. 커널 flavour 고르기

모듈 패키지 이름의 끝부분(flavour)은 **설치된 커널 계열**을 따라가야 한다.

```bash
dpkg-query -W -f='${Status}\n' linux-image-generic-hwe-22.04
```

| 결과 | 써야 할 패키지 |
| --- | --- |
| `install ok installed` (HWE 커널) | `linux-modules-nvidia-595-generic-hwe-22.04` |
| 설치 안 됨 (GA 커널) | `linux-modules-nvidia-595-generic` |

두 패키지가 **둘 다 존재하기 때문에** 아무거나 고르면 안 된다. GA 쪽 후보는 5.15 커널용(`5.15.0-190.200`)이라 6.8 커널에서는 모듈이 맞지 않는다.

버전이 박힌 이름(`linux-modules-nvidia-595-6.8.0-138-generic`) 대신 flavour 메타패키지를 쓰는 이유는, **앞으로 커널이 올라가도 맞는 서명 모듈이 자동으로 따라오게** 하기 위해서다.

---

## 5. 수동 설치 절차

```bash
sudo apt update

# 반드시 두 패키지를 함께 지정한다
sudo apt install linux-modules-nvidia-595-generic-hwe-22.04 nvidia-driver-595

sudo reboot
```

`ultra-p3` 에서 dry-run 으로 확인한 결과: 580 계열 21개가 제거되고 595 계열 23개가 설치된다. 정상적인 교체이며 `dkms` 는 포함되지 않는다.

실행 전에 무엇이 바뀌는지 직접 보고 싶다면:

```bash
apt-get install -s linux-modules-nvidia-595-generic-hwe-22.04 nvidia-driver-595 \
  | grep -E "^(Inst|Remv)"
```

> apt 가 도는 동안 화면은 그대로 유지된다. 실행 중인 커널 모듈은 재부팅 전까지 메모리에 남아있기 때문이다. 다만 이 상태에서 CUDA 앱을 새로 띄우면 라이브러리와 커널 모듈 버전이 어긋나 실패한다. 바로 재부팅하는 편이 좋다.

---

## 6. Ansible role 로 하기

위 절차를 [`nvidia_driver`](../roles/nvidia_driver/) role 로 옮겨놨다. 커널 flavour 판별, Secure Boot 확인, DKMS 혼입 검사를 자동으로 한다.

```bash
ansible-playbook -i hosts_local playbooks/linux/upgrade_nvidia_driver.yml -K \
  -e nvidia_driver_min_version=595.58.03 \
  -e nvidia_driver_prime_mode=nvidia
```

role 이 설치 전에 막아주는 것들:

- 요청한 브랜치가 저장소에 없음 → 중단
- 저장소 후보 버전이 `nvidia_driver_min_version` 미달 → 중단
- **설치 시뮬레이션에 `nvidia-dkms` 가 섞임** → 중단 (3장의 사고를 막는 핵심 검사)
- Secure Boot 가 켜져 있는데 `nvidia_driver_use_prebuilt_modules=false` → 중단

자세한 변수 목록은 [roles/nvidia_driver/README.md](../roles/nvidia_driver/README.md) 참조.

---

## 7. 재부팅 후 검증

```bash
# 1) 드라이버 버전
nvidia-smi
#    Driver Version: 595.84 로 나오면 성공

# 2) 커널 모듈이 실제로 올라왔는지
lsmod | grep nvidia

# 3) 모듈 서명 확인 (Secure Boot 환경에서 의미 있는 확인)
modinfo nvidia | grep -E "^(version|signer)"
#    version: 595.84
#    signer:  Canonical Ltd. Kernel Module Signing   ← 이 줄이 있어야 한다

# 4) Vulkan 이 NVIDIA GPU 를 잡는지 (Isaac Sim 이 실제로 쓰는 경로)
#    vulkan-tools 가 필요하다. isaac_sim role 이 설치해 주지만 없으면:
#    sudo apt install vulkan-tools
vulkaninfo --summary | grep -i deviceName
```

재부팅 전까지 `nvidia-smi` 는 **예전 버전을 계속 보고한다.** 정상이다. `nvidia_driver` role 도 설치된 패키지 버전과 실행 중 버전을 비교해 재부팅이 필요하다는 사실을 마지막에 알려준다.

---

## 8. 하이브리드 GPU (PRIME) — Isaac Sim 을 쓸 거라면

```bash
prime-select query
```

`on-demand` 면 Intel 내장 GPU 가 화면을 담당하고 NVIDIA 는 요청한 앱만 쓴다. 이 모드에서 **Omniverse Kit(Isaac Sim)이 GPU 를 잡지 못하고 종료되는 경우**가 있다.

```bash
sudo prime-select nvidia
sudo reboot
```

`on-demand` 를 유지한 채 개별 앱만 NVIDIA 로 돌리려면:

```bash
__NV_PRIME_RENDER_OFFLOAD=1 __VK_LAYER_NV_optimus=NVIDIA_only \
  ~/.local/bin/isaac-sim-ros2.sh
```

시행착오를 줄이려면 Isaac Sim 설치 **전에** `nvidia` 로 고정해 두는 편이 낫다.

---

## 9. 브랜치 선택 기준

### 어느 브랜치로 갈 것인가

| 브랜치 | 저장소 후보 | 판단 |
| --- | --- | --- |
| 580 | 580.173.02 | Isaac Sim 6.0 요구치(595.58.03) **미달** |
| **595** | **595.84** | Isaac Sim 6.0 이 검증한 브랜치. **권장** |
| 610 | 610.43.02 | 더 새것이지만 Omniverse 검증 범위 밖. 앞서갈 이유 없음 |

### `-open` 변형을 쓸 것인가

`ubuntu-drivers devices` 는 `nvidia-driver-595-open` 을 recommended 로 표시한다. Turing 이후 GPU(Ada 포함)에서 동작하고 NVIDIA 도 이쪽을 기본으로 가고 있다.

다만 **이미 proprietary 를 쓰고 있다면 그대로 두는 편이 안전하다.** 드라이버 업그레이드와 모듈 종류 변경을 한 번에 하면, 문제가 생겼을 때 원인이 둘 중 어느 쪽인지 가려내기 어렵다. 바꾸려면 업그레이드가 안정된 뒤 따로 한다.

`nvidia_driver` role 에서는 `-e nvidia_driver_open=true` 로 전환한다.

---

## 10. 문제 해결

### 재부팅 후 화면이 안 뜬다 / `nvidia-smi` 가 실패한다

거의 대부분 커널 모듈이 안 올라온 경우다.

```bash
# Ctrl+Alt+F3 으로 TTY 진입 후
lsmod | grep nvidia          # 비어있으면 모듈 미로드
sudo dmesg | grep -iE "nvidia|Lockdown|module verification"
#   "Loading of unsigned module is rejected" → 서명 문제 (DKMS 로 빠진 것)
```

복구:

```bash
sudo apt install --reinstall linux-modules-nvidia-595-generic-hwe-22.04
sudo reboot
```

TTY 조차 안 들어가지면 GRUB 메뉴에서 `e` 를 눌러 커널 파라미터에 `nomodeset` 을 추가해 부팅한 뒤 위 명령을 실행한다.

### 이전 버전으로 되돌리기

580 은 저장소에 그대로 남아있으므로 같은 방식으로 되돌린다.

```bash
sudo apt install linux-modules-nvidia-580-generic-hwe-22.04 nvidia-driver-580
sudo reboot
```

### 구 브랜치 잔여 패키지가 남아있을 때

```bash
sudo apt autoremove
dpkg -l | grep -E "nvidia" | grep -v 595    # 595 외 잔재 확인
```

### `apt-cache policy` 출력이 한글이라 스크립트가 깨질 때

파싱하는 자리에서는 로케일을 고정한다. `nvidia_driver` role 도 같은 이유로 관련 태스크에 `LC_ALL=C` 를 걸어두었다.

```bash
LC_ALL=C apt-cache policy nvidia-driver-595
```

---

## 참고

- [roles/nvidia_driver/README.md](../roles/nvidia_driver/README.md) — role 상세
- [roles/isaac_sim/README.md](../roles/isaac_sim/README.md) — Isaac Sim 설치 (드라이버 595.58.03 이상 요구)
- [Isaac Sim — 시스템 요구사항](https://docs.isaacsim.omniverse.nvidia.com/latest/installation/requirements.html)
- [Ubuntu — NVIDIA drivers installation](https://ubuntu.com/server/docs/how-to/graphics/install-nvidia-drivers/)
