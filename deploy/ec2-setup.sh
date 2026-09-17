#!/usr/bin/env bash
# EC2(Ubuntu 22.04/24.04) 최초 세팅 스크립트
# 사용법: ssh로 EC2 접속 후 이 스크립트를 실행
#   chmod +x ec2-setup.sh && ./ec2-setup.sh
set -e

echo "[1/4] 패키지 업데이트"
sudo apt-get update -y
sudo apt-get install -y ca-certificates curl gnupg git

echo "[2/4] Docker 공식 저장소 등록"
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
sudo chmod a+r /etc/apt/keyrings/docker.gpg

echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

echo "[3/4] Docker + Compose 플러그인 설치"
sudo apt-get update -y
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

echo "[4/4] 현재 사용자를 docker 그룹에 추가"
sudo usermod -aG docker "$USER"

echo ""
echo "설치 완료. 그룹 권한 적용을 위해 아래 중 하나를 실행하세요:"
echo "  - 재접속(SSH 재로그인), 또는"
echo "  - newgrp docker"
echo ""
echo "이후 프로젝트 디렉토리에서 다음을 실행하면 됩니다:"
echo "  docker compose up -d --build"
