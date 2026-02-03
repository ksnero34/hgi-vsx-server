#!/bin/bash

# 저장할 디렉토리 생성
SAVE_DIR="dist"
mkdir -p $SAVE_DIR

# 이미지 목록
IMAGES=(
    "harbor.hwgeneralins.com/hgi-vsx/openvsx-webui:0.31.0"
    "harbor.hwgeneralins.com/hgi-vsx/openvsx-server:0.31.0"
    "harbor.hwgeneralins.com/hgi-vsx/openvsx-cli:0.31.0"
)

echo "이미지 저장을 시작합니다..."

# 각 이미지를 개별적으로 저장
for image in "${IMAGES[@]}"; do
    # 이미지 이름에서 슬래시와 콜론을 언더스코어로 변경하여 파일 이름 생성
    filename=$(echo $image | sed 's/[\/:]/_/g')
    echo "저장 중: $image -> $SAVE_DIR/${filename}.tar.gz"
    docker save $image | gzip > "$SAVE_DIR/${filename}.tar.gz"
done

echo "모든 이미지가 $SAVE_DIR 디렉토리에 저장되었습니다." 