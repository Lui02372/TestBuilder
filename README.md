# TestBuilder — Frontend + Backend + Ollama (Docker Compose) 테스트 프로젝트

프론트엔드(Nginx 정적 페이지) → 백엔드(FastAPI) → Ollama(로컬 LLM) 로 이어지는
최소 구성 예제입니다. 로컬에서 `docker compose up`으로 바로 띄워볼 수 있고,
동일한 구성을 그대로 EC2에 배포할 수 있습니다.

## 구조

```
TestBuilder/
├── frontend/           # Nginx로 서빙되는 정적 페이지 (prompt 입력 → /api/chat 호출)
│   ├── public/index.html
│   ├── nginx.conf      # /api/ 요청을 backend 컨테이너로 프록시
│   └── Dockerfile
├── backend/            # FastAPI (prompt를 받아 Ollama에 위임)
│   ├── main.py
│   ├── requirements.txt
│   └── Dockerfile
├── docker-compose.yml  # frontend + backend + ollama + ollama-pull(모델 자동 다운로드)
├── .env.example
└── deploy/
    ├── ec2-setup.sh    # EC2(Ubuntu)에 Docker 설치하는 스크립트
    └── DEPLOY.md       # EC2 배포 절차 (보안그룹, 실행, 확인 방법)
```

## 요청 흐름

```
브라우저 → (80) frontend(nginx) → /api/* 프록시 → (8000) backend(FastAPI)
                                                        → (11434) ollama → 모델 추론
```

- Ollama는 인증이 없는 API이므로 외부에 직접 노출하지 않고, docker-compose 내부 네트워크로만 backend와 통신합니다.
- 프론트는 항상 상대경로 `/api/chat`만 호출하므로, 로컬이든 EC2든 코드 수정 없이 그대로 동작합니다.

## 로컬 실행

```bash
cp .env.example .env
docker compose up -d --build

# 모델 다운로드 진행 확인 (최초 1회, 수 분 소요)
docker compose logs -f ollama-pull
```

모델 준비가 끝나면 브라우저에서 `http://localhost` 접속.

## EC2 배포

[deploy/DEPLOY.md](deploy/DEPLOY.md) 참고. 요약:

1. Ubuntu EC2 인스턴스 생성 (t3.medium 이상 권장, 최소 4GB RAM)
2. 보안그룹: 22(SSH), 80(프론트) 오픈 / 11434(Ollama)는 오픈하지 않음
3. `deploy/ec2-setup.sh` 실행 → Docker 설치
4. 프로젝트 clone → `.env` 설정 → `docker compose up -d --build`
5. `http://<EC2_PUBLIC_IP>` 접속해서 확인

## 로컬 개발 환경 (backend venv)

```powershell
cd backend
python -m venv .venv
.\.venv\Scripts\Activate.ps1
pip install -r requirements.txt -r requirements-dev.txt
pytest -v
```

## 문서

- [doc/docker-command-guide.md](doc/docker-command-guide.md) — Docker / Compose 명령어 학습 가이드
- [doc/cicd-guide.md](doc/cicd-guide.md) — GitHub Actions CI/CD (EC2 자동 배포) 설정

## 다른 모델로 바꾸기

`.env`의 `OLLAMA_MODEL` 값을 바꾸고 재시작하면 됩니다.

```bash
OLLAMA_MODEL=llama3.2:3b
```

```bash
docker compose up -d --build
docker compose logs -f ollama-pull
```

## 참고: 프론트/백엔드 역할 분배 관점

- **백엔드**: Ollama API 스펙(`/api/generate`)을 감싸서 팀 내부 API 스펙(`/api/chat`)으로 노출.
  프론트는 Ollama의 존재를 몰라도 되고, 나중에 모델을 바꾸거나 다른 LLM 제공자로 교체해도
  백엔드 내부만 수정하면 됩니다.
- **프론트엔드**: `/api/chat` 스펙만 알면 되므로, 백엔드가 아직 미완성이어도 mock 응답으로
  먼저 화면을 개발할 수 있습니다.
- **인프라**: EC2 한 대에 컨테이너 3개(frontend/backend/ollama)를 올리는 가장 단순한 구성이며,
  트래픽이 늘어나면 EC2를 늘리거나 Ollama만 별도 GPU 인스턴스로 분리하는 방향으로 확장 가능합니다.
