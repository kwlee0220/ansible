# isaac_sim

Ubuntu 22.04(jammy)에 NVIDIA Isaac Sim standalone 배포판을 설치하고, 시스템에 설치된 ROS 2 Humble 과 연동할 수 있는 실행 환경을 만든다.

## 무엇을 하는가

1. **사전 검사** — Ubuntu 릴리즈, NVIDIA 드라이버 버전(`nvidia-smi`), ROS 2 설치 여부, 디스크 여유 공간(압축 파일만 약 13GiB)을 먼저 확인한다.
2. **런타임 의존성** — Omniverse Kit 실행에 필요한 Vulkan/X11 라이브러리 설치, `nofile` 한계 상향.
3. **Isaac Sim 설치** — standalone zip 을 받아 `~/isaacsim` 에 풀고 `post_install.sh` 를 실행한다. 이미 설치돼 있으면 통째로 건너뛴다.
4. **ROS 2 브리지 환경** — `ros-humble-vision-msgs` / `ros-humble-ackermann-msgs` / `ros-humble-simulation-interfaces` 설치. 마지막 것은 `isaacsim.ros2.sim_control` 확장이 여는 서비스(`/set_entity_state`, `/set_simulation_state`)를 ROS 쪽에서 **부르기 위한** 타입이다 — 없으면 물체 재배치와 Play/Stop 제어가 **조용히** 막힌다. UDP 전용 Fast DDS 프로파일은 기본으로 배치하지 않는다 (`isaac_sim_install_fastdds_profile`, 아래 참조).
5. **ROS 2 워크스페이스** — `IsaacSim-ros_workspaces` 의 `humble_ws` 를 `rosdep` + `colcon` 으로 빌드한다.
6. **실행 래퍼** — `~/.local/bin/isaac-sim-ros2.sh` 와 데스크톱 항목 생성.

ROS 2 자체는 설치하지 않는다. `ros2` role 이 담당한다.

## 설치

```bash
# ROS 2 Humble 설치 (아직 안 했다면)
ansible-playbook -i hosts_local playbooks/rdfp/install_rdfp_infra.yml -K

# Isaac Sim 설치
ansible-playbook -i hosts_local playbooks/rdfp/install_isaac_sim.yml -K
```

13GiB 를 받고 워크스페이스까지 빌드하므로, 먼저 `--check` 로 전제 조건만 확인해 볼 수 있다.
드라이버·디스크·ROS 2 조회는 실제로 수행하고 설치·빌드는 건너뛴다.

```bash
ansible-playbook -i hosts_local playbooks/rdfp/install_isaac_sim.yml -K --check
```

## 대상 컴퓨터에서 Isaac Sim 실행하기

설치는 Ansible 이 하지만 **실행은 대상 컴퓨터의 데스크톱 세션에서** 해야 한다. Vulkan/X11 GUI 애플리케이션이라 SSH 로는 뜨지 않는다. 물리 콘솔이나 원격 데스크톱([xrdp](../xrdp/) role) 세션에서 실행할 것.

### 실행 경로

| 방법 | 명령 | 비고 |
| --- | --- | --- |
| **실행 래퍼** | `~/.local/bin/isaac-sim-ros2.sh` | ROS 2 환경을 잡고 GUI 실행. **기본** |
| 데스크톱 항목 | 앱 메뉴 → `Isaac Sim (<version>)` | 같은 래퍼를 호출한다 |
| 맨몸 실행 | `~/isaacsim/isaac-sim.sh` | ROS 2 브리지 없이 시뮬레이터만 |

`~/.local/bin` 이 PATH 에 있으면 파일 이름만 쳐도 된다. 래퍼에 준 인자는 그대로 `isaac-sim.sh` 로 전달된다.

```bash
isaac-sim-ros2.sh              # GUI
isaac-sim-ros2.sh --no-window  # headless
```

**첫 실행은 셰이더 캐시를 굽느라 5~10분 걸린다.** 창이 한참 안 뜨는 것이 정상이다.

### 래퍼가 잡아주는 환경

`.bashrc` 를 건드리지 않는 대신 래퍼 프로세스 안에서만 아래를 설정한다 (이유는 [ROS 2 연동에서 중요한 점](#ros-2-연동에서-중요한-점) 참조).

```bash
source /opt/ros/humble/setup.bash
source ~/isaacsim_ros_ws/humble_ws/install/local_setup.bash   # 빌드돼 있으면
export RMW_IMPLEMENTATION=rmw_fastrtps_cpp
export ROS_DOMAIN_ID=31
export FASTRTPS_DEFAULT_PROFILES_FILE=~/.ros/fastdds.xml
```

그래서 **래퍼로 띄워야 ROS 2 브리지가 붙는다.** `isaac-sim.sh` 를 직접 실행하면 시뮬레이터는 뜨지만 토픽이 나가지 않는다.

### 다른 터미널에서 ROS 2 로 붙기

래퍼는 Isaac Sim **자기 프로세스에만** 환경을 건다. 토픽을 보려는 터미널에서는 같은 값을 직접 맞춰야 한다.

```bash
source /opt/ros/humble/setup.bash
source ~/isaacsim_ros_ws/humble_ws/install/local_setup.bash
export RMW_IMPLEMENTATION=rmw_fastrtps_cpp
export ROS_DOMAIN_ID=31
export FASTRTPS_DEFAULT_PROFILES_FILE=~/.ros/fastdds.xml

ros2 topic list
```

RMW 나 `ROS_DOMAIN_ID` 가 어긋나면 **에러 없이 토픽이 그냥 안 보인다.** `ros2` role 이 `rmw-cyclonedds-cpp` 도 설치하므로 터미널 기본값이 다를 수 있다.

브리지 확장(`isaacsim.ros2.bridge`)은 따로 켤 필요 없다 — 아래 [ROS 2 연동에서 중요한 점](#ros-2-연동에서-중요한-점) 참조.

### 실행 전 점검

NVIDIA 가 배포판에 넣어둔 자체 검사기가 드라이버 / Vulkan / GPU 를 한 번에 확인해 준다.

```bash
~/isaacsim/isaac-sim.compatibility_check.sh
```

### 안 뜰 때

| 증상 | 원인 | 대처 |
| --- | --- | --- |
| 창이 안 뜨고 조용히 종료 | 하이브리드 GPU 에서 `prime-select` 가 `on-demand` | 아래 참조 |
| `Too many open files` | `nofile` 상향이 아직 세션에 반영 안 됨 | 재로그인 (pam_limits 는 로그인 세션에만 적용된다) |
| Vulkan 초기화 실패 | 드라이버가 `isaac_sim_required_driver_version` 미달 | [nvidia_driver](../nvidia_driver/) role 로 올린 뒤 재부팅 |
| 시뮬레이터는 뜨는데 토픽이 없음 | 맨몸 `isaac-sim.sh` 로 실행했거나 RMW 불일치 | 래퍼 사용 / 위의 환경 맞추기 |

`prime-select query` 가 `on-demand` 면 Omniverse Kit 이 NVIDIA GPU 를 못 잡고 종료되는 경우가 있다. 그때만 우회하려면:

```bash
__NV_PRIME_RENDER_OFFLOAD=1 __VK_LAYER_NV_optimus=NVIDIA_only \
  ~/.local/bin/isaac-sim-ros2.sh
```

아예 고정하는 편이 확실하다.

```bash
sudo prime-select nvidia && sudo reboot
```

### 실제로 깔린 버전 확인

`install.yml` 은 `~/isaacsim/isaac-sim.sh` 가 이미 있으면 다운로드를 통째로 건너뛴다. 손으로 받아둔 예전 버전이 그 자리에 있으면 `isaac_sim_version` 을 올려도 **새 버전을 받지 않는다.** 래퍼와 데스크톱 항목에는 새 버전 번호가 찍히므로 헷갈리기 쉽다.

```bash
cat ~/isaacsim/VERSION
```

버전을 바꾸려면 `~/isaacsim` 을 비우고 다시 돌린다.

## ROS 2 연동에서 중요한 점

- **환경변수를 `~/.bashrc` 에 넣지 말 것.** 특히 Isaac Sim 내장 ROS 2 라이브러리 경로를 `LD_LIBRARY_PATH` 에 전역으로 걸면 `rviz2` 등 시스템 ROS 2 도구가 그 라이브러리를 먼저 잡아 실행에 실패한다. 그래서 이 role 은 `.bashrc` 를 건드리지 않고 실행 래퍼 안에서만 환경을 설정한다.
- **RMW 를 통일할 것.** 브리지는 CycloneDDS 도 지원하지만(2024년부터), 이 role 은 Fast DDS(`rmw_fastrtps_cpp`)를 기본으로 쓴다. `ros2` role 이 `rmw-cyclonedds-cpp` 도 설치하므로, 다른 터미널에서 `RMW_IMPLEMENTATION=rmw_cyclonedds_cpp` 를 쓰면 토픽이 **에러 없이** 서로 보이지 않는다. `ROS_DOMAIN_ID` 도 맞춰야 한다. 선택 근거와 실측 비교는 [dds-middleware.md](dds-middleware.md) 참조.
- **`isaac_sim_install_fastdds_profile` 은 기본 `false` 다.** 이 프로파일은 공유메모리 전송을 끄고 UDP 만 쓰게 하는데, 켜면 같은 호스트에서 카메라 토픽 전송량이 약 1,200배로 늘어난다(46 MB 기준 40 KB → 48.6 MB, 실측). `true` 로 둘 상황은 Isaac Sim 과 노드가 **같은 호스트의 서로 다른 컨테이너**에 있을 때뿐이다. 노드가 **다른 머신**에 있는 것은 켤 이유가 아니다 — SHM 을 켜 둬도 원격과는 자동으로 UDP 를 쓴다. RMW 가 Fast DDS 가 아니면 이 프로파일은 적용되지 않는다.
- **노드가 다른 머신에 있으면 `isaac_sim_fastdds_whitelist_default_iface=true` 를 줄 것.** Fast DDS 는 `127.0.0.1` 도 로케이터로 announce 하고 원격 상대가 그리로도 데이터를 한 벌 더 보내, 전달량만큼을 그대로 버린다(실측 46 MB 전달에 46 MB 낭비). 실제 IP 만 announce 하게 하면 사라지며, 공유메모리는 그대로 유지된다.
- **브리지 확장은 따로 설치하지 않는다.** `isaacsim.ros2.bridge` 는 패키지에 포함돼 있고, ROS 2 환경이 잡힌 터미널에서 실행하면 자동으로 활성화된다.

## 주요 변수

| 변수 | 기본값 | 설명 |
| --- | --- | --- |
| `isaac_sim_version` | `6.0.1` | 설치할 버전. 바꾸면 `isaac_sim_zip_checksum` 도 갱신하거나 `""` 로 비운다 |
| `isaac_sim_install_dir` | `~/isaacsim` | 설치 경로 |
| `isaac_sim_keep_archive` | `false` | 압축 해제 후 13GiB zip 을 남길지 |
| `isaac_sim_ros_distro` | `humble` | 연동할 ROS 2 배포판 |
| `isaac_sim_use_internal_ros2` | `false` | 시스템 ROS 2 대신 내장 ROS 2 라이브러리 사용 |
| `isaac_sim_rmw_implementation` | `rmw_fastrtps_cpp` | 래퍼가 설정하는 RMW |
| `isaac_sim_install_fastdds_profile` | `false` | Fast DDS 전송 프로파일 배치 ([dds-middleware.md](dds-middleware.md)) |
| `isaac_sim_fastdds_disable_shm` | `false` | 프로파일에서 공유메모리 전송 제거. 컨테이너 구성일 때만 |
| `isaac_sim_fastdds_whitelist_default_iface` | `false` | 기본 IPv4 만 announce. **노드가 다른 머신에 있으면 켤 것** |
| `isaac_sim_fastdds_interface_whitelist` | `[]` | announce 할 주소를 직접 지정 |
| `isaac_sim_ros_domain_id` | `31` | 래퍼가 설정하는 도메인 ID. rdfp 스택에 맞춘 값 |
| `isaac_sim_build_ros_workspace` | `true` | `humble_ws` 빌드 여부 |
| `isaac_sim_driver_check` | `true` | `nvidia-smi` 드라이버 버전 검사 |
| `isaac_sim_required_driver_version` | `595.58.03` | 6.0.x Linux 최소 드라이버 |
| `isaac_sim_disk_check` / `isaac_sim_required_disk_gib` | `true` / `60` | 여유 공간 검사 |

## 요구 사항

- RT 코어가 있는 NVIDIA RTX GPU (A100/H100 은 지원되지 않는다)
- NVIDIA 독점 드라이버 595.58.03 이상 — 부족하면 [nvidia_driver](../nvidia_driver/) role 로 먼저 올린다
- RAM 32GiB 이상, 여유 공간 60GiB 이상
- 하이브리드(내장 GPU + NVIDIA) 구성이면 `prime-select` 가 `nvidia` 여야 안전하다 (`nvidia_driver_prime_mode=nvidia`)
- WSL 은 지원 대상이 아니다 (`validate.yml` 에서 막는다)
- `community.general` 컬렉션 (`pam_limits`)

## 참고

- [dds-middleware.md](dds-middleware.md) — Fast DDS vs CycloneDDS 비교, SHM 설정, 실측
- [Isaac Sim — Linux 설치](https://docs.isaacsim.omniverse.nvidia.com/latest/installation/install_workstation.html)
- [Isaac Sim — 다운로드](https://docs.isaacsim.omniverse.nvidia.com/latest/installation/download.html)
- [Isaac Sim — ROS 2 설치/연동](https://docs.isaacsim.omniverse.nvidia.com/6.0.0/installation/install_ros.html)
- [IsaacSim-ros_workspaces](https://github.com/isaac-sim/IsaacSim-ros_workspaces)
