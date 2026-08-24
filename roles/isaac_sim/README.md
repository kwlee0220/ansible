# isaac_sim

Ubuntu 22.04(jammy)에 NVIDIA Isaac Sim standalone 배포판을 설치하고,
시스템에 설치된 ROS 2 Humble 과 연동할 수 있는 실행 환경을 만든다.

## 무엇을 하는가

1. **사전 검사** — Ubuntu 릴리즈, NVIDIA 드라이버 버전(`nvidia-smi`),
   ROS 2 설치 여부, 디스크 여유 공간(압축 파일만 약 13GiB)을 먼저 확인한다.
2. **런타임 의존성** — Omniverse Kit 실행에 필요한 Vulkan/X11 라이브러리 설치,
   `nofile` 한계 상향.
3. **Isaac Sim 설치** — standalone zip 을 받아 `~/isaacsim` 에 풀고
   `post_install.sh` 를 실행한다. 이미 설치돼 있으면 통째로 건너뛴다.
4. **ROS 2 브리지 환경** — `ros-humble-vision-msgs` / `ros-humble-ackermann-msgs`
   설치, `~/.ros/fastdds.xml`(UDP 전용 프로파일) 배치.
5. **ROS 2 워크스페이스** — `IsaacSim-ros_workspaces` 의 `humble_ws` 를
   `rosdep` + `colcon` 으로 빌드한다.
6. **실행 래퍼** — `~/.local/bin/isaac-sim-ros2.sh` 와 데스크톱 항목 생성.

ROS 2 자체는 설치하지 않는다. `ros2` role 이 담당한다.

## 실행

```bash
# ROS 2 Humble 설치 (아직 안 했다면)
ansible-playbook -i hosts_local playbooks/rdfp/install_rdfp_infra.yml -K

# Isaac Sim 설치
ansible-playbook -i hosts_local playbooks/rdfp/install_isaac_sim.yml -K
```

설치가 끝나면:

```bash
~/.local/bin/isaac-sim-ros2.sh              # ROS 2 환경을 잡고 GUI 실행
~/.local/bin/isaac-sim-ros2.sh --no-window  # headless
```

첫 실행은 셰이더 캐시를 굽느라 5~10분 걸린다.

## ROS 2 연동에서 중요한 점

- **환경변수를 `~/.bashrc` 에 넣지 말 것.** 특히 Isaac Sim 내장 ROS 2 라이브러리
  경로를 `LD_LIBRARY_PATH` 에 전역으로 걸면 `rviz2` 등 시스템 ROS 2 도구가
  그 라이브러리를 먼저 잡아 실행에 실패한다. 그래서 이 role 은 `.bashrc` 를
  건드리지 않고 실행 래퍼 안에서만 환경을 설정한다.
- **RMW 를 통일할 것.** Isaac Sim 의 ROS 2 브리지는 Fast DDS(`rmw_fastrtps_cpp`)
  기준으로 검증돼 있다. `ros2` role 이 `rmw-cyclonedds-cpp` 도 설치하므로,
  다른 터미널에서 `RMW_IMPLEMENTATION=rmw_cyclonedds_cpp` 를 쓰면 토픽이
  서로 보이지 않는다. `ROS_DOMAIN_ID` 도 맞춰야 한다.
- **브리지 확장은 따로 설치하지 않는다.** `isaacsim.ros2.bridge` 는 패키지에
  포함돼 있고, ROS 2 환경이 잡힌 터미널에서 실행하면 자동으로 활성화된다.

## 주요 변수

| 변수 | 기본값 | 설명 |
| --- | --- | --- |
| `isaac_sim_version` | `6.0.1` | 설치할 버전. 바꾸면 `isaac_sim_zip_checksum` 도 갱신하거나 `""` 로 비운다 |
| `isaac_sim_install_dir` | `~/isaacsim` | 설치 경로 |
| `isaac_sim_keep_archive` | `false` | 압축 해제 후 13GiB zip 을 남길지 |
| `isaac_sim_ros_distro` | `humble` | 연동할 ROS 2 배포판 |
| `isaac_sim_use_internal_ros2` | `false` | 시스템 ROS 2 대신 내장 ROS 2 라이브러리 사용 |
| `isaac_sim_rmw_implementation` | `rmw_fastrtps_cpp` | 래퍼가 설정하는 RMW |
| `isaac_sim_ros_domain_id` | `0` | 래퍼가 설정하는 도메인 ID |
| `isaac_sim_build_ros_workspace` | `true` | `humble_ws` 빌드 여부 |
| `isaac_sim_driver_check` | `true` | `nvidia-smi` 드라이버 버전 검사 |
| `isaac_sim_required_driver_version` | `595.58.03` | 6.0.x Linux 최소 드라이버 |
| `isaac_sim_disk_check` / `isaac_sim_required_disk_gib` | `true` / `60` | 여유 공간 검사 |

## 요구 사항

- RT 코어가 있는 NVIDIA RTX GPU (A100/H100 은 지원되지 않는다)
- NVIDIA 독점 드라이버 595.58.03 이상 — 부족하면 [nvidia_driver](../nvidia_driver/) role 로 먼저 올린다
- RAM 32GiB 이상, 여유 공간 60GiB 이상
- 하이브리드(내장 GPU + NVIDIA) 구성이면 `prime-select` 가 `nvidia` 여야 안전하다
  (`nvidia_driver_prime_mode=nvidia`)
- WSL 은 지원 대상이 아니다 (`validate.yml` 에서 막는다)
- `community.general` 컬렉션 (`pam_limits`)

## 참고

- [Isaac Sim — Linux 설치](https://docs.isaacsim.omniverse.nvidia.com/latest/installation/install_workstation.html)
- [Isaac Sim — 다운로드](https://docs.isaacsim.omniverse.nvidia.com/latest/installation/download.html)
- [Isaac Sim — ROS 2 설치/연동](https://docs.isaacsim.omniverse.nvidia.com/6.0.0/installation/install_ros.html)
- [IsaacSim-ros_workspaces](https://github.com/isaac-sim/IsaacSim-ros_workspaces)
