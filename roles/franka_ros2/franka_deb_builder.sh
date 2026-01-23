#!/bin/bash
set -e

# 1. 환경 설정
WS_DIR="$HOME/franka_ros2_ws"
DIST_DIR="$HOME/franka_debs_output"
ROS_DISTRO="humble"

echo "=== 1. 환경 준비 및 디렉토리 생성 ==="
mkdir -p $DIST_DIR

cd $WS_DIR/src

# 2. 개별 패키지 빌드 루프
echo "=== 2. 패키징 프로세스 시작 ==="

# package.xml이 있는 모든 하위 디렉토리를 찾아 빌드 수행
find . -maxdepth 3 -name "package.xml" | while read pkg_xml; do
    PKG_DIR=$(dirname $pkg_xml)
    PKG_NAME=$(basename $PKG_DIR)
    
    echo "------------------------------------------------"
    echo "대상 패키지: $PKG_NAME"
    echo "경로: $PKG_DIR"
    
    cd $WS_DIR/src/$PKG_DIR
    
    # 이전 빌드 기록 삭제
    rm -rf debian/ obj-x86_64-linux-gnu/
    
    echo ">>> Bloom 메타데이터 생성 중..."
    if bloom-generate rosdebian --ros-distro $ROS_DISTRO; then
        echo ">>> 바이너리 패키징(.deb) 빌드 중..."
        if fakeroot debian/rules binary; then
            echo ">>> [성공] $PKG_NAME 빌드 완료"
        else
            echo ">>> [실패] $PKG_NAME 빌드 중 오류 발생"
        fi
    else
        echo ">>> [건너뜀] $PKG_NAME (Bloom 생성 실패 - 메타패키지일 수 있음)"
    fi
    
    cd $WS_DIR/src
done

# 3. 결과물 수집
echo "=== 3. 생성된 .deb 파일 수집 ==="
find $WS_DIR/src -name "*.deb" -exec cp {} $DIST_DIR \;

echo "================================================"
echo "작업 완료!"
echo "생성된 파일 위치: $DIST_DIR"
ls -lh $DIST_DIR
echo "================================================"
