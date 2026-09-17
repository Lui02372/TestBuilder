#!/usr/bin/env bash
# EC2 (Amazon Linux 2023, 사용자: ec2-user) 최초 세팅 스크립트
# 설치: git, rsync, Docker, Docker Compose 플러그인, Buildx 플러그인
# 사용법: ssh로 EC2 접속 후 실행
#   chmod +x ec2-setup.sh && ./ec2-setup.sh
# 이미 설치된 항목은 건너뛰므로 여러 번 실행해도 안전합니다.
set -e

ARCH=$(uname -m)                      # x86_64 또는 aarch64 (Graviton)
case "$ARCH" in
  x86_64)  BUILDX_ARCH=amd64 ;;
  aarch64) BUILDX_ARCH=arm64 ;;
  *) echo "지원하지 않는 아키텍처: $ARCH" >&2; exit 1 ;;
esac
PLUGIN_DIR=/usr/local/lib/docker/cli-plugins

echo "[1/5] 패키지 설치 (git, rsync, docker)"
sudo dnf install -y git rsync docker

echo "[2/5] Docker 서비스 시작 + 부팅 시 자동 시작"
sudo systemctl enable --now docker

echo "[3/5] Docker Compose 플러그인 설치"
sudo mkdir -p "$PLUGIN_DIR"
if docker compose version >/dev/null 2>&1; then
  echo "  이미 설치됨: $(docker compose version)"
else
  sudo curl -fsSL \
    "https://github.com/docker/compose/releases/latest/download/docker-compose-linux-${ARCH}" \
    -o "$PLUGIN_DIR/docker-compose"
  sudo chmod +x "$PLUGIN_DIR/docker-compose"
fi

echo "[4/5] Docker Buildx 플러그인 설치 (docker compose build 에 필요)"
if docker buildx version >/dev/null 2>&1; then
  echo "  이미 설치됨: $(docker buildx version)"
else
  BUILDX_VERSION=$(curl -fsSL https://api.github.com/repos/docker/buildx/releases/latest \
    | grep '"tag_name"' | head -1 | cut -d '"' -f 4)
  sudo curl -fsSL \
    "https://github.com/docker/buildx/releases/download/${BUILDX_VERSION}/buildx-${BUILDX_VERSION}.linux-${BUILDX_ARCH}" \
    -o "$PLUGIN_DIR/docker-buildx"
  sudo chmod +x "$PLUGIN_DIR/docker-buildx"
fi

echo "[5/5] 현재 사용자($USER)를 docker 그룹에 추가"
sudo usermod -aG docker "$USER"

echo ""
echo "설치 결과:"
git --version
docker --version
docker compose version
docker buildx version
echo ""
echo "그룹 권한 적용을 위해 아래 중 하나를 실행하세요:"
echo "  - exit 후 SSH 재접속 (권장), 또는"
echo "  - newgrp docker"
echo ""
echo "이후 프로젝트 디렉토리에서:"
echo "  cd ~/TestBuilder && cp -n .env.example .env && docker compose up -d --build"
