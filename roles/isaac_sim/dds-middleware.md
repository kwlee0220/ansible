# DDS 미들웨어 선택 — Fast DDS vs CycloneDDS

Isaac Sim 의 ROS 2 브리지에서 어느 RMW 를 쓸지, 공유메모리(SHM)를 어떻게 살릴지
정리한 문서. 아래 수치는 전부 실측값이다. (2026-08-25)

측정 환경:

| | 호스트 | 주소 | GPU |
| --- | --- | --- | --- |
| A (퍼블리셔) | `master` | 192.168.0.134 | RTX 4090 |
| B (원격 구독자, [6장](#6-shm-과-네트워크는-공존한다--크로스머신-실측)에서만) | `ultra-p3` | 192.168.0.2 | RTX 4000 SFF Ada |

둘 다 Ubuntu 22.04.5 + ROS 2 Humble, 같은 서브넷.

**결론부터: Fast DDS 를 쓴다. UDP 전용 프로파일은 켜지 않는다.**
둘 다 role 기본값이므로 도메인만 맞추면 된다.

```bash
ansible-playbook -i hosts_local playbooks/rdfp/install_isaac_sim.yml -K \
  -e isaac_sim_ros_domain_id=<맞출 도메인>
```

이유는 [9장](#9-무엇을-고를-것인가). 가장 큰 이유는 `fastdds.xml` 프로파일이
같은 호스트에서 **전송량을 1,200배로 늘린다**는 점이다([4장](#4-성능-실측)).
이 측정 때문에 `isaac_sim_install_fastdds_profile` 기본값을 `true` 에서 `false` 로
바꿨다.

---

## 1. RMW 는 고정이 아니다

Isaac Sim 의 브리지가 Fast DDS 전용이라는 얘기가 돌지만, **지금은 사실이 아니다**.

**근거 1 — 런타임 스위처가 들어있다.** 배포판에 `librmw_implementation.so` 가 있고, 이건 ROS 2 의 RMW 동적 선택 계층이다.

```console
$ strings librmw_implementation.so | grep -E 'RMW_IMPLEMENTATION|functions.cpp'
failed to fetch RMW_IMPLEMENTATION from environment due to %s
RMW_IMPLEMENTATION
/workspace/humble_ws/src/rmw_implementation/src/functions.cpp
```

`RMW_IMPLEMENTATION` 환경변수를 읽어 `librmw_<impl>.so` 를 dlopen 한다.
`rmw_fastrtps_cpp` 는 **컴파일 타임 기본값**일 뿐이다.

**근거 2 — Cyclone RMW 가 함께 번들돼 있다.**

```console
$ ls exts/isaacsim.ros2.core/{humble,jazzy}/lib | grep -E 'librmw_(fastrtps|cyclonedds)_cpp'
librmw_cyclonedds_cpp.so
librmw_fastrtps_cpp.so
```

CycloneDDS 코어(`libddsc.so.0.10.5`)도 같이 들어있다. 즉 `isaac_sim_use_internal_ros2=true`
로 내장 ROS 2 를 쓰는 경우에도 Cyclone 을 고를 수 있다.

**근거 3 — 배포판의 `setup_ros_env.sh` 가 기본값만 채운다.**

```bash
if [ -z "$RMW_IMPLEMENTATION" ]; then
    export RMW_IMPLEMENTATION="rmw_fastrtps_cpp"
fi
```

**근거 4 — 브리지 CHANGELOG 의 공식 이력** (`exts/isaacsim.ros2.bridge/docs/CHANGELOG.md`)

| 버전 | 날짜 | 내용 |
| --- | --- | --- |
| 0.2.6 | 2022-03-11 | "Removed Cyclone DDS to allow defualt FastRTPS DDS to run instead" |
| 2.16.0 | 2024-04-04 | "Isaac Sim now supports CycloneDDS (Linux ROS2 Humble only)" |
| 4.9.3 | 2025-07-29 | "CycloneDDS is now supported for Jazzy" |

"Fast DDS 전용"은 2022년 얘기이고 2024년에 풀렸다. 설치본의 브리지는 5.1.1 (2026-04-27)이라 Humble·Jazzy 모두 지원 범위 안이다.

---

## 2. 이 저장소의 현재 상태

`ros2` role 은 `rmw-cyclonedds-cpp` 를 설치하지만([roles/ros2/defaults/main.yml](../ros2/defaults/main.yml)) **어디서도 `RMW_IMPLEMENTATION` 을 설정하지 않는다.** 셸 환경을 건드리지 않는다는 role 의 방침 때문이다. 그래서 아무것도 설정하지 않은 터미널은 Humble 기본값을 쓴다.

```console
$ source /opt/ros/humble/setup.bash
$ echo "${RMW_IMPLEMENTATION:-(unset)}"
(unset)
$ python3 -c "from rclpy.impl.implementation_singleton import rclpy_implementation as r; print(r.rclpy_get_rmw_implementation_identifier())"
rmw_fastrtps_cpp
```

즉 **이 머신의 "설정 안 한" 상태는 이미 Fast DDS 다.** Cyclone 을 고른다는 것은 모든 터미널·모든 노드·모든 컨테이너가 명시적으로 opt-in 해야 한다는 뜻이고, 한 군데만 빠뜨리면 에러 없이 토픽이 안 보인다.

설치된 관련 패키지:

| 패키지 | 버전 |
| --- | --- |
| `ros-humble-rmw-fastrtps-cpp` | 6.2.10 |
| `ros-humble-rmw-cyclonedds-cpp` | 1.3.4 |
| `ros-humble-cyclonedds` | 0.10.5 |
| `ros-humble-iceoryx-{binding-c,posh,hoofs}` | 2.0.5 |

---

## 3. 공유메모리(SHM) 설정 방법

같은 호스트에서 대용량 토픽(카메라·포인트클라우드)을 주고받으면 SHM 사용 여부가 성능을 지배한다. 두 미들웨어의 방식이 다르다.

### 3.1 Fast DDS — 기본으로 켜져 있다

별도 설정이 필요 없다. Fast DDS 는 SHM 전송을 빌트인 전송으로 기본 포함한다. **끄는 설정을 하지 않는 것**이 전부다.

문제는 이 role 이 배포하는 `~/.ros/fastdds.xml` 이 정확히 그것을 끈다는 점이다 ([templates/fastdds.xml.j2](templates/fastdds.xml.j2)).

```xml
<userTransports>
    <transport_id>UdpTransport</transport_id>   <!-- UDPv4 만 -->
</userTransports>
<useBuiltinTransports>false</useBuiltinTransports>   <!-- SHM 포함 빌트인 전송 제거 -->
```

이 프로파일은 Isaac Sim 과 ROS 2 노드가 **같은 호스트의 서로 다른 컨테이너**에 있을 때 discovery 실패를 막는 용도다. 같은 호스트에서 그냥 돌린다면 켤 이유가 없고, 켜면 손해만 본다([4장](#4-성능-실측)).

**다른 머신과 통신하는 것은 이 프로파일을 켤 이유가 아니다.** SHM 을 켜 둬도 원격
상대와는 자동으로 UDP 를 쓴다([6장](#6-shm-과-네트워크는-공존한다--크로스머신-실측)).

```bash
# 같은 호스트 구성이면 끈다
-e isaac_sim_install_fastdds_profile=false
```

### 3.2 CycloneDDS — Iceoryx 를 통해서만, 명시적으로

CycloneDDS 의 SHM 은 [Iceoryx](https://iceoryx.io/) 연동이다. 세 가지가 필요하다.

**(1) `iox-roudi` 데몬을 먼저 띄운다.** 어떤 ROS 2 노드보다 먼저 떠 있어야 한다.

```bash
source /opt/ros/humble/setup.bash
/opt/ros/humble/bin/iox-roudi &
```

**(2) `CYCLONEDDS_URI` 로 SHM 을 켠다.** 기본은 꺼져 있다.

```xml
<?xml version="1.0" encoding="UTF-8" ?>
<CycloneDDS xmlns="https://cdds.io/config">
  <Domain id="any">
    <SharedMemory>
      <Enable>true</Enable>
      <LogLevel>info</LogLevel>
    </SharedMemory>
  </Domain>
</CycloneDDS>
```

```bash
export CYCLONEDDS_URI=file:///home/<user>/.ros/cyclonedds.xml
```

**(3) 메시지가 4 MiB 를 넘지 않아야 한다.** RouDi 기본 mempool 의 최대 chunk payload 가 4,194,304 B 다. 넘으면 **폴백 없이 publish 가 실패한다**([5장](#5-cyclonedds-의-4-mib-벽)).

> 가변 크기 타입도 SHM 을 탄다. `librmw_cyclonedds_cpp.so` 의 "Publishing a loaned message of non fixed type is not allowed" 는 zero-copy **loan API**(`rmw_borrow_loaned_message`)에만 걸리는 제약이고, 일반 publish 의 SHM 전송 경로와는 무관하다. `sensor_msgs/Image` 로 확인했다.

---

## 4. 성능 실측

### 측정 방법

- 퍼블리셔와 서브스크라이버를 **별도 프로세스**로 띄운다. (같은 프로세스면 DDS 와 무관하게 단축 경로를 타서 판별이 안 된다.)
- `sensor_msgs/msg/Image` 를 50회 발행한다.
- `/sys/class/net/lo/statistics/tx_bytes` 의 증분으로 loopback 전송량을 잰다. SHM 을 타면 페이로드가 네트워크 스택을 통과하지 않으므로 값이 작게 남는다.
- 재현 스크립트는 [11장](#11-재현-방법).

### 4.1 VGA — 640×480 RGB (921,600 B × 50 = 46,080,000 B)

| 구성 | loopback 전송량 | 수신 |
| --- | ---: | --- |
| **Fast DDS 기본** | **40,560 B** | 50/50 |
| Fast DDS + role 의 `fastdds.xml` | 48,630,598 B | 50/50 |
| CycloneDDS 기본 (SHM off) | 48,905,278 B | 50/50 |
| **CycloneDDS + SHM + RouDi** | **34,696 B** | 50/50 |

SHM 을 타는 두 구성은 페이로드가 loopback 에 전혀 나타나지 않는다(남은 수만 바이트는 discovery 트래픽). **양쪽 다 SHM 이 정상 동작한다.**

핵심은 2행이다. **role 기본값 그대로 두면 46 MB 를 통째로 loopback 으로 밀어낸다 — 40 KB 로 될 일을 48.6 MB 로 하는 셈이라 약 1,200배다.**

### 4.2 HD — 1920×1080 RGB (6,220,800 B × 50 = 311,040,000 B)

| 구성 | loopback 전송량 | 수신 |
| --- | ---: | --- |
| **Fast DDS 기본** | 37,868 B | **50/50** |
| CycloneDDS + SHM | 34,574 B | **0/50** |

CycloneDDS 쪽은 한 장도 전달되지 않았다. 3회 반복해도 같았다.

---

## 5. CycloneDDS 의 4 MiB 벽

HD 프레임에서 실패한 이유다.

```
[ Fatal ]: The following mempools are available:
  MemPool [ ChunkSize = 168,     ChunkPayloadSize = 128,     ChunkCount = 10000 ]
  MemPool [ ChunkSize = 1064,    ChunkPayloadSize = 1024,    ChunkCount = 5000 ]
  MemPool [ ChunkSize = 16424,   ChunkPayloadSize = 16384,   ChunkCount = 1000 ]
  MemPool [ ChunkSize = 131112,  ChunkPayloadSize = 131072,  ChunkCount = 200 ]
  MemPool [ ChunkSize = 524328,  ChunkPayloadSize = 524288,  ChunkCount = 50 ]
  MemPool [ ChunkSize = 1048616, ChunkPayloadSize = 1048576, ChunkCount = 30 ]
  MemPool [ ChunkSize = 4194344, ChunkPayloadSize = 4194304, ChunkCount = 10 ]
Could not find a fitting mempool for a chunk of size 6220952
[Warning]: ICEORYX error! MEPOO__MEMPOOL_GETCHUNK_CHUNK_IS_TOO_LARGE
```

그리고 퍼블리셔에서:

```
RCLError: Failed to publish: failed to publish data, at ./src/rmw_node.cpp:1837
```

**네트워크 전송으로 폴백하지 않는다.** SHM 으로 못 보내면 그냥 실패한다. Isaac Sim 카메라를 HD 이상으로 뽑는 순간 바로 걸린다.

RouDi 커스텀 mempool 설정으로 늘릴 수는 있다.

```bash
iox-roudi -c /etc/iceoryx/roudi_config.toml
```

다만 이건 **정적으로 선할당되는 공유메모리**라, 시스템에서 가장 큰 메시지에 맞춰 크기와 개수를 계속 동기화해야 하는 설정 파일이 하나 더 생긴다. Fast DDS 에는 대응하는 제약이 없다.

---

## 6. SHM 과 네트워크는 공존한다 — 크로스머신 실측

"SHM 을 켜면 다른 컴퓨터와 통신이 안 되는가?" 아니다. Fast DDS 는 **상대별로 전송을 고른다.** 같은 서브넷의 두 대 (A = `192.168.0.134`, B = `ultra-p3` `192.168.0.2`)로 확인했다.

### 6.1 다섯 가지 경우

퍼블리셔는 항상 A. 페이로드는 4장과 같은 921,600 B × 50 = 46,080,000 B. **A 의 `lo` 송신량이 판정 기준**이다 — 작으면 로컬 전달이 SHM 을 탄 것이고, 46 MB 에 가까우면 UDP 로 떨어진 것이다.

구독자 조합과 B 의 로케이터 설정을 바꿔 가며 다섯 가지를 쟀다.

| # | 로컬 구독자 | 원격 구독자 | B 의 loopback 로케이터 | A `lo` 송신 | 로컬 수신 | 원격 수신 |
| --- | --- | --- | --- | ---: | --- | --- |
| 1 | ✓ | ✓ | announce | 50,858,834 | 50/50 | 50/50 |
| 2 | ✗ | ✓ | announce | 51,703,044 | — | 50/50 |
| 3 | ✓ | ✗ | — | 48,530 | 50/50 | — |
| 4 | ✗ | ✗ | — | 4,342 | — | — |
| 5 | ✓ | ✓ | **억제** | **44,372** | 50/50 | 50/50 |

각 경우가 무엇을 보려는 것이고 무엇을 말해 주는지, 논리 순서대로:

- **케이스 4 — 구독자 없음 (바닥값).**
  4,342 B. 아무도 안 듣는 상태의 participant announce 트래픽만이다. 나머지 경우의 `lo` 수치를 이 값과 비교해서 읽는다.

- **케이스 3 — 로컬 전용 (양성 대조군).**
  48,530 B. 4번보다 44 KB 늘었을 뿐, **46 MB 페이로드는 `lo` 를 전혀 통과하지 않았다.** 늘어난 44 KB 는 구독자가 붙으면서 생긴 discovery 증가분이다. 같은 호스트 전달이 SHM 을 탄다는 것을 여기서 확인한다.

- **케이스 2 — 원격 전용 (원인 분리).**
  51,703,044 B. **로컬 구독자가 아예 없는데** 페이로드만큼이 `lo` 에 흘렀다. 즉 이 트래픽은 로컬 전달과 무관하다. 정체는 [6.2](#62-기본-설정의-숨은-낭비--원격-참가자의-127001-로케이터) 에서 밝힌다.

- **케이스 1 — 로컬 + 원격 (본래 질문).**
  50,858,834 B. 2번과 거의 같다. **로컬 구독자를 추가했는데 `lo` 가 늘지 않았다** — 늘었다면 46 MB 가 더해져 97 MB 가 됐어야 한다. 따라서 로컬 전달은 여전히 SHM 이고, 51 MB 는 2번과 같은 원인이다.

- **케이스 5 — 로컬 + 원격, 원인 제거 (결론).**
  44,372 B. 2번에서 드러난 원인(B 가 `127.0.0.1` 을 로케이터로 announce)을 제거하자 3번 수준으로 돌아왔는데, **양쪽 구독자가 모두 50/50 을 받았다.**

**케이스 5 가 결론이다.** 로컬과 원격 구독자가 동시에 전부 수신하는데 `lo` 에는 44 KB(discovery 뿐)만 흘렀다. 로컬은 SHM, 원격은 UDP 로 간 것이다.
**원격 통신 때문에 SHM 을 포기할 이유가 없다.**

### 6.2 기본 설정의 숨은 낭비 — 원격 참가자의 `127.0.0.1` 로케이터

케이스 1·2 는 처음엔 반증처럼 보인다. `lo` 에 51 MB 가 흘렀기 때문이다. 그런데 **케이스 2 는 로컬 구독자가 아예 없는데도** 그랬다. 목적지를 보면:

```console
$ tcpdump -nn -r lo.pcap | awk '{print $5}' | sort | uniq -c | sort -rn | head -3
    953 127.0.0.1.39161      <- 51 MB 의 대부분
     27 239.255.0.1.39150    <- discovery 멀티캐스트
```

멀티캐스트가 아니라 **`127.0.0.1` 유니캐스트**다. 원인은 B 가 participant 를 announce 할 때 로케이터 목록에 **자기 `127.0.0.1` 을 함께 넣기** 때문이다. RTPS 라이터는 매칭된 리더가 announce 한 유니캐스트 로케이터 **전부**로 보내므로, A 는 같은 샘플을 `192.168.0.2` 로 한 번, **A 자신의 `127.0.0.1` 로 또 한 번** 보낸다. 후자는 아무도 듣지 않는 포트에 도착해 버려진다.

**전달량 대비 100% 오버헤드다.** Isaac Sim 이 카메라 토픽을 원격 노드로 보내면 대역폭과 CPU 를 두 배로 쓴다. 같은 호스트만 쓸 때는 나타나지 않으므로, 로컬에서 잘 돌던 구성을 두 대로 늘린 뒤에야 드러난다.

### 6.3 대응 — 실제 IP 만 announce 하게 한다

각 머신이 자기 인터페이스만 announce 하도록 화이트리스트를 건다.
**SHM 은 그대로 유지된다** — 두 transport descriptor 를 함께 등록하면 된다.

role 변수로 켠다. 머신마다 주소를 적을 필요 없이 기본 인터페이스를 자동으로 쓴다.

```bash
ansible-playbook -i hosts_local playbooks/rdfp/install_isaac_sim.yml -K \
  -e isaac_sim_fastdds_whitelist_default_iface=true
```

주소를 직접 지정하려면 `isaac_sim_fastdds_interface_whitelist` 에 목록으로 준다.
어느 쪽이든 프로파일 배치가 자동으로 켜지므로 `isaac_sim_install_fastdds_profile`
을 따로 줄 필요는 없다.

[templates/fastdds.xml.j2](templates/fastdds.xml.j2) 가 만드는 결과:

```xml
<transport_descriptors>
    <transport_descriptor>
        <transport_id>ShmTransport</transport_id>
        <type>SHM</type>
    </transport_descriptor>
    <transport_descriptor>
        <transport_id>UdpTransport</transport_id>
        <type>UDPv4</type>
        <interfaceWhiteList>
            <address>192.168.0.134</address>
        </interfaceWhiteList>
    </transport_descriptor>
</transport_descriptors>

<participant profile_name="isaac_sim_transport" is_default_profile="true">
    <rtps>
        <userTransports>
            <transport_id>ShmTransport</transport_id>
            <transport_id>UdpTransport</transport_id>
        </userTransports>
        <useBuiltinTransports>false</useBuiltinTransports>
    </rtps>
</participant>
```

`useBuiltinTransports=false` 는 기본 전송을 전부 걷어내므로, SHM 을 쓰려면
위처럼 SHM descriptor 를 **명시적으로** 등록해야 한다. 이것을 빠뜨리면
화이트리스트는 걸리지만 SHM 이 사라져 같은 호스트 전달까지 UDP 로 떨어진다.

**실측** — 로컬·원격 구독자를 동시에 붙이고 46,080,000 B 를 보냈을 때
A 의 `lo` 송신량:

| 구성 | A `lo` 송신 | `/dev/shm` fastrtps 세그먼트 | 로컬 수신 | 원격 수신 |
| --- | ---: | ---: | --- | --- |
| 프로파일 없음 | 49,451,608 | 5 | 50/50 | 50/50 |
| 화이트리스트만 (SHM descriptor 누락) | 46,239,996 | **0** | 50/50 | 50/50 |
| **SHM + 화이트리스트** | **29,304** | 5 | 50/50 | 50/50 |

가운데 줄이 위에서 말한 함정이다. 낭비는 사라졌지만 SHM 도 같이 사라져
같은 호스트 전달이 UDP 로 떨어졌다(세그먼트 0개). 맨 아래가 role 이 만드는 구성이다.

## 7. 크로스머신 처리량 — 1280×720 카메라 기준

"Fast DDS 는 대용량 메시지에 약하다"는 통념을 실제 카메라 해상도로 확인했다. **결론: 이 조건에서는 성립하지 않는다.** 30 fps 이하에서는 차이가 없고, 포화 근처에서는 오히려 Fast DDS 가 낫다.

### 7.1 조건

- A(`master`) 발행 → B(`ultra-p3`) 수신. 1 Gbps, MTU 1500, RTT 0.8 ms
- `sensor_msgs/Image` **1280×720 rgb8 = 2,764,800 B** (프레임당 UDP 조각 약 1,878개 — 여기서 미들웨어 차이가 드러난다)
- 각 10초, **기본 소켓 버퍼**(`net.core.rmem_max` = 212,992) 그대로
- rclpy(Python) 노드

1 Gbps 에서 이 프레임의 이론 최대는 약 42 fps 다.

### 7.2 결과

| QoS | 목표 fps | RMW | 달성 fps | 전송률 | 손실 | 퍼블리셔 CPU |
| --- | ---: | --- | ---: | ---: | --- | ---: |
| BEST_EFFORT | 10 | Fast DDS | 10.0 | 27.6 MB/s | 1/100 | 3.15 s |
| BEST_EFFORT | 10 | Cyclone | 10.0 | 27.6 MB/s | 0 | 3.46 s |
| BEST_EFFORT | 30 | Fast DDS | 30.0 | 82.9 MB/s | 1/300 | 4.53 s |
| BEST_EFFORT | 30 | Cyclone | 30.0 | 82.9 MB/s | 0 | 5.65 s |
| RELIABLE | 30 | Fast DDS | 30.0 | 82.9 MB/s | 0 | 5.18 s |
| RELIABLE | 30 | Cyclone | 30.0 | 82.9 MB/s | 0 | 4.48 s |
| BEST_EFFORT | 40 | **Fast DDS** ×3 | **40.0 / 40.0 / 40.0** | **110.6 MB/s** | 1, 1, 2 /400 | 5.27 / 5.94 / 5.78 s |
| BEST_EFFORT | 40 | **Cyclone** ×3 | **35.2 / 34.7 / 35.0** | ~96.7 MB/s | 0, 0, 0 | 6.42 / 6.72 / 6.46 s |

### 7.3 손실의 정체가 서로 다르다

빠진 시퀀스 번호를 찍어 보면 같은 "손실"이 아니다.

```
Fast DDS   MISSING seqs: [0]          <- 첫 프레임 하나. discovery 매칭 아티팩트
Cyclone    MISSING seqs: [391, 393]   <- 후반부의 실제 손실 (이 실행은 35.6 fps)
```

Fast DDS 의 손실은 레이트와 무관하게 **항상 seq 0 하나**다(10/30/40 fps 모두 1프레임). 지속 손실이 아니라 리더가 매칭되기 전에 나간 첫 샘플이다. 첫 프레임이 반드시 필요하면 RELIABLE + TRANSIENT_LOCAL 을 쓰거나 발행 전에 매칭을 기다린다.

### 7.4 해석

**30 fps(83 MB/s, 링크의 66%)까지는 실질적 차이가 없다.** 둘 다 목표 레이트를
지키고 지속 손실이 없다.

**40 fps(110 MB/s, 링크의 88%)에서 갈리고, Fast DDS 가 이긴다.**

- Fast DDS 는 목표 레이트를 유지한다. Cyclone 은 **레이트를 못 맞춘다**(약 12% 미달)
- 유효 전달량 약 **14% 차이** (110 vs 97 MB/s)
- 퍼블리셔 CPU 도 Fast DDS 가 약 **13% 적다**
- 0% 손실이라던 Cyclone 도 반복 실행에서는 실제 프레임을 떨궜다

**메커니즘 차이가 수치보다 중요하다.** Cyclone 은 `publish()` 에서 **백프레셔**를 건다 — 퍼블리셔 스레드를 붙잡아 애플리케이션 루프를 늦춘다. Fast DDS 는 프레임을 떨구고 레이트를 지킨다. Isaac Sim 에서는 후자가 낫다. DDS 때문에 시뮬레이션 스텝이 밀리는 것이 프레임 하나 잃는 것보다 나쁘기 때문이다.

### 7.5 이 측정의 한계

- **기본 소켓 버퍼로만 쟀다.** 대용량 메시지의 표준 튜닝(`net.core.rmem_max` 상향)을 적용하면 양쪽 다 개선될 여지가 있고 격차도 달라질 수 있다.
- rclpy(Python) 기준이다. C++ 노드는 절대 수치가, 특히 CPU 가 다르다.
- 1 Gbps 라 40 fps 가 이미 88% 포화다. 10 GbE 에서는 갈리는 지점이 달라진다.
- **카메라 한 대(단일 스트림) 기준이다.** 총량이 같아도 스트림이 여러 개면 양상이 달라질 수 있으므로, 다중 카메라 구성은 그때 다시 재는 편이 맞다.

## 8. Isaac Sim 에서 쓸 때의 설정과 주의점

### 8.1 세 값을 전부 맞춰야 한다

Isaac Sim 과 통신할 **모든** 노드가 아래를 동일하게 가져가야 한다. 하나라도 어긋나면 **에러 없이 토픽이 안 보인다.** 이게 가장 흔한 함정이다.

| 항목 | role 변수 | 기본값 |
| --- | --- | --- |
| `RMW_IMPLEMENTATION` | `isaac_sim_rmw_implementation` | `rmw_fastrtps_cpp` |
| `ROS_DOMAIN_ID` | `isaac_sim_ros_domain_id` | `0` |
| SHM 프로파일 | `isaac_sim_install_fastdds_profile` | `true` |

래퍼([templates/isaac-sim-ros2.sh.j2](templates/isaac-sim-ros2.sh.j2))는 이 값을 **자기 프로세스에만** 건다. 다른 터미널에서는 직접 맞춰야 한다.

```bash
source /opt/ros/humble/setup.bash
source ~/isaacsim_ros_ws/humble_ws/install/local_setup.bash
export RMW_IMPLEMENTATION=rmw_fastrtps_cpp
export ROS_DOMAIN_ID=<맞출 도메인>
ros2 topic list
```

### 8.2 프로파일은 Fast DDS 일 때만 적용된다

UDP 전용 프로파일(`~/.ros/fastdds.xml`)은 **Fast DDS 전용**이다. CycloneDDS 는
`FASTRTPS_DEFAULT_PROFILES_FILE` 을 읽지 않는다.

예전에는 role 이 RMW 와 무관하게 프로파일을 배치하고 래퍼가 export 해서, Cyclone 으로
바꾸면 설정이 **조용히 무시**됐다. 지금은 두 조건을 모두 만족할 때만 동작한다.

```yaml
# vars/main.yml
_isaac_sim_uses_fastdds: "{{ isaac_sim_rmw_implementation is match('rmw_fastrtps') }}"
_isaac_sim_fastdds_profile_active: >-
  {{ (isaac_sim_install_fastdds_profile | bool) and (_isaac_sim_uses_fastdds | bool) }}
```

[tasks/ros2_bridge.yml](tasks/ros2_bridge.yml) 의 배치 태스크와
[래퍼 템플릿](templates/isaac-sim-ros2.sh.j2) 의 export 가 함께 이 값을 본다.
`rmw_fastrtps_dynamic_cpp` 도 Fast DDS 로 인식한다.

`isaac_sim_install_fastdds_profile=true` 인데 RMW 가 Fast DDS 가 아니면
[tasks/validate.yml](tasks/validate.yml) 이 경고를 띄운다 — 무시되는 설정을
켜 놓고 적용됐다고 착각하는 일을 막기 위해서다.

**CycloneDDS 에서 같은 목적(컨테이너 간 discovery)을 달성하려면 `CYCLONEDDS_URI` 로
따로 설정해야 한다.** role 은 Cyclone 용 프로파일을 제공하지 않는다.

### 8.3 Isaac Sim 내장 ROS 2 를 쓸 때

`isaac_sim_use_internal_ros2=true` 면 시스템 ROS 2 를 source 하지 않고 `exts/isaacsim.ros2.core/<distro>/lib` 를 `LD_LIBRARY_PATH` 에 얹는다. 이 경로에도 Cyclone RMW 와 `libddsc.so` 가 들어있으므로 RMW 선택은 동일하게 가능하다. 다만 **Iceoryx 바인딩(`libiceoryx_binding_c.so`)은 시스템 쪽에서 와야** 하므로, 내장 모드 + Cyclone + SHM 조합은 검증하지 않았다.

### 8.4 도메인 분리

Isaac Sim 은 시뮬레이션 토픽을 대량으로 발행한다. 실 로봇 스택과 같은 도메인에 두면 discovery 트래픽이 섞인다. 트윈마다 도메인을 나누고 `isaac_sim_ros_domain_id` 로 명시하는 편이 낫다.

---

## 9. 무엇을 고를 것인가

**Fast DDS 를 권장한다.** 이유를 무게순으로 적는다.

**1. 같은 호스트 대용량 전송에서 Fast DDS 가 설정 없이 이긴다.**
4장의 수치가 그대로다. Fast DDS 는 기본으로 SHM 을 타고 크기 제한이 없다. Cyclone 은 데몬 + 설정 파일 + mempool 튜닝을 다 해야 같은 지점에 도달하고, 4 MiB 를 넘기면 실패한다. Isaac Sim 은 카메라를 뽑는 워크로드다.

> 흔히 "대용량 메시지는 Cyclone 이 낫다"고 하는데, 이 환경에서는 어느 쪽으로도 성립하지 않았다. 같은 호스트에서는 Fast DDS 가 설정 없이 SHM 을 타고([4장](#4-성능-실측)), 크로스머신에서도 포화 근처에서 처리량·CPU 모두 앞선다([7장](#7-크로스머신-처리량--1280720-카메라-기준)).

**2. 이 머신의 기본 상태가 이미 Fast DDS 다.** ([2장](#2-이-저장소의-현재-상태)) Cyclone 을 고르면 모든 실행 경로가 명시적으로 opt-in 해야 하고, 빠뜨린 곳은 에러 없이 조용히 안 보인다. Fast DDS 를 고르면 기본 경로가 그냥 맞는다.

**3. Isaac Sim 이 스택에서 가장 유연성이 낮다.** NVIDIA 의 문서·예제·이슈가 전부 Fast DDS 전제다. Cyclone 지원은 2024년에 들어왔고 상대적으로 덜 밟혔다. GPU/Kit/RTX 층 위에 검증 안 된 DDS 조합을 얹으면 문제 발생 시 원인 분리가 어렵다.

**4. 전환 비용이 비대칭이다.** ROS 2 쪽 애플리케이션은 대개 설정 한 줄로 RMW 를 바꿀 수 있다. 반대로 Isaac Sim 을 Cyclone 으로 옮기면 8.2 의 구멍까지 같이 막아야 한다.

### Cyclone 을 고를 상황

- 기존 스택이 이미 Cyclone 으로 굳어 있고 옮기는 비용이 더 큰 경우
- 멀티캐스트가 막힌 망 등 Fast DDS discovery 가 구조적으로 안 되는 환경
- 대용량 토픽이 없고(4 MiB 미만) Cyclone 의 설정 단순함을 선호하는 경우

**어느 쪽을 고르든 절대 섞지 말 것.** 에러가 나지 않고 토픽이 없는 것처럼 보여서 디버깅에 가장 많은 시간이 든다.

---

## 10. 정리 — 권장 구성

| 상황 | 설정 |
| --- | --- |
| Isaac Sim + ROS 2 노드가 **같은 호스트** | Fast DDS. 기본값 그대로 (프로파일 `false`) |
| 노드가 **다른 머신** | Fast DDS + `isaac_sim_fastdds_whitelist_default_iface=true`. SHM 은 로컬끼리만 쓰이고 원격은 자동으로 UDP 다([6장](#6-shm-과-네트워크는-공존한다--크로스머신-실측)). 화이트리스트가 없으면 전달량만큼을 `127.0.0.1` 로 버린다([6.3](#63-대응--실제-ip-만-announce-하게-한다)) |
| 노드가 **같은 호스트의 다른 컨테이너** | `isaac_sim_install_fastdds_profile=true` + `isaac_sim_fastdds_disable_shm=true`. 컨테이너의 `/dev/shm` 크기·IPC 네임스페이스 제약을 피한다 (SHM 포기) |
| 스택이 이미 Cyclone | 전부 Cyclone 으로 통일. 프로파일은 자동으로 비활성이므로([8.2](#82-프로파일은-fast-dds-일-때만-적용된다)) `CYCLONEDDS_URI` 를 직접 준비해야 한다 |

"다른 머신"과 "다른 컨테이너"를 한 줄로 묶으면 안 된다. 머신이 다르면 SHM 은 애초에
시도조차 되지 않으므로 켜 둬도 손해가 없다. 프로파일이 필요한 것은 컨테이너 쪽이다.

**카메라 레이트 기준** (1280×720 rgb8, 1 Gbps, [7장](#7-크로스머신-처리량--1280720-카메라-기준)):

| 총 전송률 | 판단 |
| --- | --- |
| ≤ 30 fps (≈83 MB/s) | 미들웨어 선택이 성능에 영향 없음. 다른 근거로 고르면 된다 |
| 40 fps 부근 (≈110 MB/s) | 링크의 88%. Fast DDS 가 레이트를 지키고 Cyclone 은 못 지킨다 |
| 그 이상 / 다중 카메라 | 링크가 병목이다. 압축(`compressed`) 이나 10 GbE 를 먼저 검토한다 |

카메라 여러 대면 **합산**해서 본다. 10 fps 짜리 4대면 110 MB/s 로 이미 포화 구간이다.

---

## 11. 재현 방법

```bash
# 서브스크라이버
cat > /tmp/sub.py <<'PY'
import time, rclpy
from sensor_msgs.msg import Image
rclpy.init(); n = rclpy.create_node("shm_sub")
cnt = {"n": 0}
n.create_subscription(Image, "/big_image", lambda m: cnt.__setitem__("n", cnt["n"]+1), 10)
t0 = time.time()
while time.time() - t0 < 12:
    rclpy.spin_once(n, timeout_sec=0.1)
print("received", cnt["n"], flush=True)
PY

# 퍼블리셔 (W,H 를 바꿔 페이로드 크기 조절)
cat > /tmp/pub.py <<'PY'
import time, rclpy
from sensor_msgs.msg import Image
rclpy.init(); n = rclpy.create_node("shm_pub")
p = n.create_publisher(Image, "/big_image", 10)
W, H = 640, 480
msg = Image(); msg.height=H; msg.width=W; msg.encoding="rgb8"
msg.step = W*3; msg.data = bytes(W*H*3)
time.sleep(2.0)
for _ in range(50):
    p.publish(msg); time.sleep(0.02)
time.sleep(1.0)
PY

# 측정
source /opt/ros/humble/setup.bash
export ROS_DOMAIN_ID=51
export RMW_IMPLEMENTATION=rmw_fastrtps_cpp     # 또는 rmw_cyclonedds_cpp
# Fast DDS 로 SHM 을 끄고 재려면: export FASTRTPS_DEFAULT_PROFILES_FILE=~/.ros/fastdds.xml
# Cyclone 으로 SHM 을 켜려면:     iox-roudi & ; export CYCLONEDDS_URI=file:///tmp/cyclone_shm.xml

before=$(cat /sys/class/net/lo/statistics/tx_bytes)
python3 /tmp/sub.py & SUB=$!
python3 /tmp/pub.py
wait $SUB
after=$(cat /sys/class/net/lo/statistics/tx_bytes)
echo "loopback tx delta: $((after-before)) bytes"
```

CycloneDDS 가 실제로 SHM 을 잡았는지 트레이스로 확인하려면 `CYCLONEDDS_URI` 에
`<Tracing><Verbosity>finest</Verbosity><OutputFile>...</OutputFile></Tracing>` 를
넣고 `vnet iceoryx initialized` / `interface iceoryx` 줄을 찾는다.
(`<Category>iceoryx</Category>` 는 이 빌드에서 유효한 카테고리가 아니다.)

### 크로스머신(6장) 재현

두 대가 같은 서브넷에 있어야 한다(RTPS discovery 가 멀티캐스트를 쓴다).
양쪽 `ROS_DOMAIN_ID` 와 `RMW_IMPLEMENTATION` 을 맞추고, B 를 **유휴 상태**로 둔다.

```bash
# B(원격): 구독자를 띄우고 NIC 수신 카운터를 기록
ssh <user>@<B_IP> '
  cat /sys/class/net/<B_IFACE>/statistics/rx_bytes > /tmp/rx_before
  source /opt/ros/humble/setup.bash
  export RMW_IMPLEMENTATION=rmw_fastrtps_cpp ROS_DOMAIN_ID=120
  nohup python3 /tmp/sub.py > /tmp/remote.out 2>&1 &'

# A(로컬): 로컬 구독자 + 퍼블리셔를 동시에
before=$(cat /sys/class/net/lo/statistics/tx_bytes)
python3 /tmp/sub.py & python3 /tmp/pub.py; wait
after=$(cat /sys/class/net/lo/statistics/tx_bytes)
echo "A lo delta: $((after-before))"      # 작으면 로컬은 SHM

ssh <user>@<B_IP> '
  a=$(cat /sys/class/net/<B_IFACE>/statistics/rx_bytes)
  echo "B rx delta: $((a-$(cat /tmp/rx_before)))"; cat /tmp/remote.out'
```

A 의 `lo` 에 페이로드만큼이 흐른다면 6.2 의 `127.0.0.1` 로케이터 현상이다.
목적지를 확인하려면 `sudo tcpdump -i lo -nn -q udp -w lo.pcap` 로 잡아
목적지 주소별로 세어 본다.

### 처리량 벤치(7장) 재현

```python
# bpub.py — 목표 fps 로 1280x720 프레임을 count 장 발행
import sys, time, resource, rclpy
from rclpy.qos import QoSProfile, ReliabilityPolicy, HistoryPolicy
from sensor_msgs.msg import Image
count, fps, rel = int(sys.argv[1]), float(sys.argv[2]), sys.argv[3]
W, H = 1280, 720
qos = QoSProfile(depth=10 if rel=="reliable" else 5, history=HistoryPolicy.KEEP_LAST,
                 reliability=ReliabilityPolicy.RELIABLE if rel=="reliable" else ReliabilityPolicy.BEST_EFFORT)
rclpy.init(); n = rclpy.create_node("bench_pub")
p = n.create_publisher(Image, "/bench_image", qos)
msg = Image(); msg.height=H; msg.width=W; msg.encoding="rgb8"; msg.step=W*3; msg.data=bytes(W*H*3)
time.sleep(6.0)                                  # discovery
t0 = time.monotonic()
for i in range(count):
    msg.header.frame_id = str(i)                 # 손실 프레임 식별용
    p.publish(msg)
    d = t0 + (i+1)/fps - time.monotonic()
    if d > 0: time.sleep(d)
el = time.monotonic()-t0; ru = resource.getrusage(resource.RUSAGE_SELF)
time.sleep(3.0)
print(f"PUB sent={count} elapsed={el:.2f}s actual_fps={count/el:.1f} "
      f"MBps={count*W*H*3/el/1e6:.1f} cpu={ru.ru_utime+ru.ru_stime:.2f}s")
```

```python
# bsub.py — 수신 수, 유실 시퀀스, 달성 fps 를 보고
import sys, time, resource, rclpy
from rclpy.qos import QoSProfile, ReliabilityPolicy, HistoryPolicy
from sensor_msgs.msg import Image
expect, rel, dur = int(sys.argv[1]), sys.argv[2], float(sys.argv[3])
W, H = 1280, 720
qos = QoSProfile(depth=10 if rel=="reliable" else 5, history=HistoryPolicy.KEEP_LAST,
                 reliability=ReliabilityPolicy.RELIABLE if rel=="reliable" else ReliabilityPolicy.BEST_EFFORT)
rclpy.init(); n = rclpy.create_node("bench_sub")
st = {"n":0, "first":None, "last":None, "seqs":set()}
def cb(m):
    t = time.monotonic()
    if st["first"] is None: st["first"] = t
    st["last"] = t; st["n"] += 1; st["seqs"].add(int(m.header.frame_id))
n.create_subscription(Image, "/bench_image", cb, qos)
t0 = time.monotonic()
while time.monotonic()-t0 < dur: rclpy.spin_once(n, timeout_sec=0.05)
el = (st["last"]-st["first"]) if st["first"] and st["last"] else 0
uniq = len(st["seqs"])
print("MISSING seqs:", sorted(set(range(expect)) - st["seqs"])[:20])
print(f"SUB uniq={uniq}/{expect} loss={100*(expect-uniq)/expect:.1f}% "
      f"fps={uniq/el if el else 0:.1f} MBps={uniq*W*H*3/el/1e6 if el else 0:.1f}")
```

```bash
# B(원격)에서 먼저 구독자를 띄우고, A 에서 퍼블리셔를 돌린다.
# 양쪽 RMW_IMPLEMENTATION / ROS_DOMAIN_ID 를 반드시 맞출 것.
ssh <user>@<B_IP> 'source /opt/ros/humble/setup.bash
  export RMW_IMPLEMENTATION=rmw_fastrtps_cpp ROS_DOMAIN_ID=140
  nohup python3 /tmp/bsub.py 400 best_effort 26 > /tmp/b.out 2>&1 &'

source /opt/ros/humble/setup.bash
export RMW_IMPLEMENTATION=rmw_fastrtps_cpp ROS_DOMAIN_ID=140
python3 bpub.py 400 40 best_effort          # 400장, 40 fps, BEST_EFFORT

ssh <user>@<B_IP> 'cat /tmp/b.out'
```

`RMW_IMPLEMENTATION` 을 `rmw_cyclonedds_cpp` 로 바꿔 같은 조합을 반복한다.
**퍼블리셔의 `actual_fps` 가 목표에 못 미치면 미들웨어가 백프레셔를 건 것**이고,
구독자의 `MISSING seqs` 가 `[0]` 뿐이면 시작 아티팩트지 지속 손실이 아니다.

---

## 참고

- [README.md](README.md) — role 전체 설명과 실행 방법
- [Isaac Sim — ROS 2 설치/연동](https://docs.isaacsim.omniverse.nvidia.com/6.0.0/installation/install_ros.html)
- [Fast DDS — Transport 설정](https://fast-dds.docs.eprosima.com/en/latest/fastdds/transport/transport.html)
- [CycloneDDS — Shared memory](https://cyclonedds.io/docs/cyclonedds/latest/shared_memory/shared_memory.html)
- [Iceoryx — RouDi 설정](https://iceoryx.io/latest/advanced/configuration-guide/)
