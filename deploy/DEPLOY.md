# EC2 배포 가이드

## 1. EC2 인스턴스 생성

- AMI: Ubuntu 22.04 LTS (또는 24.04)
- 인스턴스 타입: **t3.medium 이상 권장** (최소 4GB RAM)
  - `llama3.2:1b` 같은 초경량 모델도 2GB 이상 여유 메모리가 필요합니다.
  - t2.micro/t3.micro 프리티어는 Ollama 구동 시 OOM으로 죽을 가능성이 높습니다.
- 스토리지: 20GB 이상 (모델 파일이 수 GB 단위)

## 2. 보안그룹(Security Group) 설정

| 포트 | 용도 | 허용 대상 |
|------|------|-----------|
| 22 | SSH | 내 IP만 |
| 80 | 프론트엔드(nginx) | 0.0.0.0/0 (팀/외부 공개용) |
| 8000 | 백엔드 직접 테스트용 | 팀 IP만 (선택) |
| 11434 | Ollama API | 열지 않는 것을 권장 (백엔드 컨테이너 내부 네트워크로만 통신) |

> Ollama(11434)는 인증이 없는 API이므로 외부에 공개하지 않고, docker-compose 내부 네트워크(`backend` → `ollama`)로만 통신하게 구성되어 있습니다.

## 3. 서버 초기 세팅

```bash
# 로컬에서 EC2로 접속
ssh -i my-key.pem ubuntu@<EC2_PUBLIC_IP>

# EC2 안에서
git clone <이 프로젝트 저장소 주소> TestBuilder
cd TestBuilder/deploy
chmod +x ec2-setup.sh
./ec2-setup.sh

# 그룹 권한 적용
newgrp docker
```

## 4. 환경변수 설정 및 실행

```bash
cd ~/TestBuilder
cp .env.example .env
# 필요하면 .env의 OLLAMA_MODEL 값을 다른 모델로 변경

docker compose up -d --build
```

## 5. 모델 다운로드 확인

`ollama-pull` 컨테이너가 자동으로 모델을 내려받습니다. 로그로 진행 상황을 확인하세요.

```bash
docker compose logs -f ollama-pull
```

`모델 준비 완료` 메시지가 뜨면 준비된 것입니다.

## 6. 동작 확인

```bash
# 백엔드 헬스체크
curl http://localhost:8000/health

# Ollama에 직접 프롬프트 테스트 (백엔드 경유)
curl -X POST http://localhost:8000/api/chat \
  -H "Content-Type: application/json" \
  -d '{"prompt":"한국어로 짧게 인사해줘"}'
```

브라우저에서 `http://<EC2_PUBLIC_IP>` 접속 → 텍스트박스에 프롬프트 입력 후 전송 버튼으로 프론트→백엔드→Ollama 전체 흐름을 확인합니다.

## 7. 운영/정리 명령어

```bash
docker compose ps            # 컨테이너 상태 확인
docker compose logs -f backend
docker compose down          # 컨테이너 정지 (모델 볼륨은 유지됨)
docker compose down -v       # 모델까지 완전히 삭제하고 싶을 때만
```

`ollama_data` 볼륨에 모델이 저장되므로, `docker compose down` 후 다시 `up` 해도 모델을 재다운로드하지 않습니다.
