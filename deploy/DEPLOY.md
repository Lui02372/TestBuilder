# EC2 배포 가이드 (Amazon Linux 2023 / ec2-user)

## 1. EC2 인스턴스 생성

- AMI: **Amazon Linux 2023** (기본 사용자: `ec2-user`)
- 인스턴스 타입: **t3.medium 이상 권장** (최소 4GB RAM)
  - `llama3.2:1b` 같은 초경량 모델도 2GB 이상 여유 메모리가 필요합니다.
  - t2.micro/t3.micro 프리티어는 Ollama 구동 시 OOM으로 죽을 가능성이 높습니다.
- 스토리지: 20GB 이상 (기본 8GB는 모델 + 이미지로 금방 가득 참)
- 키 페어: 생성한 `.pem` 파일 (예: `ec2testkeypair.pem`)

## 2. 보안그룹(Security Group) 설정

| 포트 | 용도 | 허용 대상 |
|------|------|-----------|
| 22 | SSH | 내 IP만 (GitHub Actions 자동배포를 쓰면 `0.0.0.0/0`, [cicd-guide](../doc/cicd-guide.md) 참고) |
| 80 | 프론트엔드(nginx) | 0.0.0.0/0 (팀/외부 공개용) |
| 8000 | 백엔드 직접 테스트용 | 팀 IP만 (선택) |
| 11434 | Ollama API | 열지 않는 것을 권장 (백엔드 컨테이너 내부 네트워크로만 통신) |

> Ollama(11434)는 인증이 없는 API이므로 외부에 공개하지 않고, docker-compose 내부 네트워크(`backend` → `ollama`)로만 통신하게 구성되어 있습니다.

## 3. 접속

EC2 콘솔의 **퍼블릭 IPv4 주소**를 사용합니다. (`172.31.x.x` 같은 **프라이빗 IP는 외부에서 접속 불가**)

```powershell
# 내 PC (pem 파일이 있는 폴더의 PowerShell)
ssh -i .\ec2testkeypair.pem ec2-user@<EC2_PUBLIC_IP>
```

> `UNPROTECTED PRIVATE KEY FILE` 오류가 나면 pem 권한 정리:
> `icacls .\ec2testkeypair.pem /inheritance:r` → `icacls .\ec2testkeypair.pem /grant:r "$($env:USERNAME):(R)"`

## 4. 서버 초기 세팅 (EC2 안에서, 최초 1회)

`git` 이 아직 없으면 먼저 설치 후 clone 합니다.

```bash
sudo dnf install -y git

# 저장소가 private 이므로 Username 에 GitHub 아이디, Password 에 Personal Access Token 입력
# (GitHub 비밀번호는 안 됨. 토큰 발급: GitHub → Settings → Developer settings → Personal access tokens)
git clone https://github.com/Lui02372/TestBuilder.git ~/TestBuilder

cd ~/TestBuilder/deploy
chmod +x ec2-setup.sh
./ec2-setup.sh          # git, rsync, docker, compose, buildx 설치 (이미 설치된 건 건너뜀)

exit                    # docker 그룹 적용을 위해 재접속
```

재접속 후 확인:

```bash
docker --version
docker compose version
docker ps               # permission denied 없이 빈 목록이 나오면 OK
```

> Amazon Linux 2023 의 `dnf install docker` 에는 **compose / buildx 플러그인이 포함되어 있지 않습니다.**
> `docker compose` 가 `unknown command` 로 나오면 `ec2-setup.sh` 를 다시 실행하세요.

## 5. 환경변수 설정 및 실행

```bash
cd ~/TestBuilder
cp -n .env.example .env        # -n: 이미 .env 가 있으면 덮어쓰지 않음
# 필요하면 .env의 OLLAMA_MODEL 값을 다른 모델로 변경

docker compose up -d --build
docker compose ps
```

## 6. 모델 다운로드 확인

`ollama-pull` 컨테이너가 자동으로 모델을 내려받습니다.

```bash
docker compose logs -f ollama-pull
```

`모델 준비 완료` 메시지가 뜨면 준비된 것입니다. (Ctrl+C 로 로그 보기 종료)

## 7. 동작 확인

```bash
# 백엔드 헬스체크
curl http://localhost:8000/health

# Ollama에 직접 프롬프트 테스트 (백엔드 경유)
curl -X POST http://localhost:8000/api/chat \
  -H "Content-Type: application/json" \
  -d '{"prompt":"한국어로 짧게 인사해줘"}'
```

브라우저에서 `http://<EC2_PUBLIC_IP>` 접속 → 텍스트박스에 프롬프트 입력 후 전송 버튼으로 프론트→백엔드→Ollama 전체 흐름을 확인합니다.

## 8. 코드 업데이트

- **GitHub Actions 자동배포를 설정했다면**: 내 PC 에서 `git push` 만 하면 됩니다. ([cicd-guide](../doc/cicd-guide.md))
- **수동으로 할 때** (EC2 안에서):

```bash
cd ~/TestBuilder
git pull
docker compose up -d --build
```

> 자동배포와 수동 `git pull` 을 섞으면 서버 파일 상태가 꼬일 수 있으니 한 가지 방식만 쓰세요.

## 9. 운영/정리 명령어

```bash
docker compose ps            # 컨테이너 상태 확인
docker compose logs -f backend
docker stats                 # 메모리 사용량 (Ollama OOM 확인)
df -h                        # 디스크 여유 공간
docker compose down          # 컨테이너 정지 (모델 볼륨은 유지됨)
docker compose down -v       # 모델까지 완전히 삭제하고 싶을 때만
docker image prune -f        # 재빌드로 쌓인 옛 이미지 정리
```

`ollama_data` 볼륨에 모델이 저장되므로, `docker compose down` 후 다시 `up` 해도 모델을 재다운로드하지 않습니다.
