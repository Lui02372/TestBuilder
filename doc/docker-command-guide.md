# Docker Command Guide (TestBuilder 실습용)

이 프로젝트(`frontend` / `backend` / `ollama` / `ollama-pull`)를 기준으로 Docker 명령어를 익히는 문서입니다.
모든 `docker compose ...` 명령은 **`docker-compose.yml`이 있는 폴더(`TestBuilder/`)에서** 실행합니다.

---

## 0. 먼저 개념 정리

| 용어 | 비유 | 설명 |
|------|------|------|
| **이미지(Image)** | 설계도 / 붕어빵 틀 | `Dockerfile`로 빌드한 실행 패키지. 그 자체로는 실행되지 않음 |
| **컨테이너(Container)** | 붕어빵 | 이미지를 실행한 것. 실제로 떠서 동작하는 프로세스 |
| **볼륨(Volume)** | 외장하드 | 컨테이너를 지워도 남는 데이터 (`ollama_data` = 모델 파일) |
| **네트워크(Network)** | 사내망 | 컨테이너끼리 서비스 이름(`backend`, `ollama`)으로 통신 |
| **Compose** | 오케스트라 지휘자 | 여러 컨테이너를 `docker-compose.yml` 하나로 한꺼번에 관리 |

### Q. `docker compose up -d` 했는데, 실행됐는지는 어디서 봐요? `docker run` 해야 하나요?

**`docker run`은 하지 마세요.** `docker compose up -d`가 이미 이미지를 빌드하고 **컨테이너까지 실행**한 상태입니다.
실행 여부는 **컨테이너 목록**에서 확인합니다.

```bash
docker compose ps        # 이 프로젝트 컨테이너만 보기 (추천)
docker ps                # PC/서버 전체에서 실행 중인 컨테이너
docker ps -a             # 멈춘(Exited) 컨테이너까지 전부
```

정상이라면 대략 이렇게 보입니다.

```
NAME          SERVICE       STATUS
backend       backend       Up 2 minutes    0.0.0.0:8000->8000/tcp
frontend      frontend      Up 2 minutes    0.0.0.0:80->80/tcp
ollama        ollama        Up 2 minutes    0.0.0.0:11434->11434/tcp
```

- `ollama-pull`은 모델을 받고 **종료되는 게 정상**이라 `docker compose ps -a`로 보면 `Exited (0)`입니다.
- `Exited (1)` 같은 0이 아닌 코드 / `Restarting` 이 반복되면 문제 → `docker compose logs <서비스명>` 으로 원인 확인.
- Docker Desktop(Windows)을 쓴다면 GUI의 **Containers** 탭에서도 같은 내용을 볼 수 있습니다.

> `docker run`은 compose 없이 **이미지 하나를 단독으로** 띄울 때 쓰는 명령입니다.
> compose로 띄운 서비스를 `docker run`으로 또 띄우면 이름/포트 충돌이 나거나, compose 네트워크에 안 붙어서 `backend → ollama` 통신이 안 됩니다.

---

## 1. Compose 명령어 (이 프로젝트에서 가장 많이 씀)

### 실행 / 중지

```bash
docker compose up -d --build     # 빌드 + 백그라운드 실행 (코드 바꿨으면 --build 필수)
docker compose up -d             # 빌드 없이 실행 (이미지 이미 있을 때)
docker compose up                # 포그라운드 실행 (로그가 화면에 계속 나옴, Ctrl+C 로 종료)

docker compose stop              # 컨테이너 정지 (삭제 X, start 로 다시 켤 수 있음)
docker compose start             # 정지된 컨테이너 다시 시작
docker compose restart backend   # 특정 서비스만 재시작

docker compose down              # 컨테이너 + 네트워크 삭제 (볼륨=모델은 유지)
docker compose down -v           # 볼륨까지 삭제 ⚠️ 모델 재다운로드 필요
```

### 상태 / 로그

```bash
docker compose ps                    # 실행 중인 서비스
docker compose ps -a                 # 종료된 것 포함 (ollama-pull 확인용)
docker compose logs                  # 전체 로그
docker compose logs -f backend       # backend 로그 실시간 보기 (Ctrl+C 로 빠져나옴)
docker compose logs --tail 50 ollama # 마지막 50줄만
docker compose logs -f ollama-pull   # 모델 다운로드 진행 상황
docker compose top                   # 각 컨테이너 안에서 도는 프로세스
```

### 특정 서비스만 다루기

```bash
docker compose build backend              # backend 이미지만 다시 빌드
docker compose up -d --build backend      # backend 만 재빌드 + 재시작
docker compose up -d --no-deps frontend   # 의존 서비스는 건드리지 않고 frontend 만
```

### 설정 확인

```bash
docker compose config    # .env 값이 치환된 최종 compose 설정 출력 (오타 검사에 유용)
docker compose images    # 이 프로젝트가 사용하는 이미지 목록
```

---

## 2. 컨테이너 안으로 들어가기 / 명령 실행

```bash
docker compose exec backend sh            # backend 컨테이너 쉘 접속 (exit 로 나옴)
docker compose exec backend python -V     # 들어가지 않고 명령만 실행
docker compose exec ollama ollama list    # 받아진 모델 목록 확인
docker compose exec ollama ollama pull llama3.2:3b   # 모델 수동 다운로드
docker compose exec ollama ollama run llama3.2:1b "안녕"  # 모델 직접 테스트
docker compose exec frontend nginx -t     # nginx 설정 문법 검사
```

> `exec`는 **이미 실행 중인** 컨테이너에 명령을 보냅니다. 컨테이너가 꺼져 있으면 동작하지 않습니다.

---

## 3. 단일 컨테이너 명령어 (`docker ...`)

compose 없이 쓰는 기본 명령어. 컨테이너 이름(`backend`, `ollama` 등)이나 ID로 지정합니다.

```bash
docker ps / docker ps -a         # 컨테이너 목록
docker logs -f backend           # 로그
docker exec -it backend sh       # 쉘 접속 (-it = 대화형 터미널)
docker stop backend              # 정지
docker start backend             # 시작
docker restart backend           # 재시작
docker rm backend                # 삭제 (정지 상태여야 함, 강제는 -f)
docker inspect backend           # 상세 정보(JSON): 환경변수, IP, 마운트 등
docker stats                     # CPU/메모리 실시간 사용량 (Ollama 메모리 확인할 때 유용)
docker port frontend             # 포트 매핑 확인
```

### `docker run` 연습 (compose 와 별개로 실습용)

```bash
# 이미지를 직접 빌드하고 단독 실행해보기
docker build -t testbuilder-frontend ./frontend
docker run -d --name fe-test -p 8080:80 testbuilder-frontend
#          │   │              │         └ 사용할 이미지
#          │   │              └ 호스트 8080 → 컨테이너 80
#          │   └ 컨테이너 이름
#          └ 백그라운드 실행
# → http://localhost:8080 접속 (단, /api 호출은 backend 가 같은 네트워크에 없어서 실패함)

docker rm -f fe-test             # 실습 끝나면 정리

# 일회성 컨테이너 (--rm: 종료되면 자동 삭제)
docker run --rm python:3.11-slim python -c "print('hello')"
```

---

## 4. 이미지 / 볼륨 / 네트워크

```bash
docker images                        # 이미지 목록
docker rmi <이미지>                   # 이미지 삭제
docker pull ollama/ollama:latest     # 이미지 받기

docker volume ls                     # 볼륨 목록 (testbuilder_ollama_data 가 모델 저장소)
docker volume inspect testbuilder_ollama_data

docker network ls                    # 네트워크 목록 (testbuilder_default)
docker network inspect testbuilder_default   # 어떤 컨테이너가 붙어있는지
```

> compose 가 만드는 볼륨/네트워크 이름 앞에는 **프로젝트 이름(= 폴더 이름 소문자)** 이 붙습니다.

---

## 5. 정리(용량 확보)

```bash
docker system df            # Docker 가 쓰는 디스크 용량 확인
docker image prune -f       # 태그 없는(dangling) 이미지 삭제 — 재빌드 반복하면 쌓임
docker container prune -f   # 멈춘 컨테이너 전부 삭제
docker system prune -f      # 안 쓰는 컨테이너/네트워크/이미지 한꺼번에
docker system prune -a --volumes   # ⚠️ 안 쓰는 것 전부 + 볼륨까지 (모델도 날아감)
```

EC2 디스크(20GB)는 금방 찹니다. 배포를 여러 번 했다면 `docker system df` → `docker image prune -f` 습관을 들이세요.

---

## 6. 이 프로젝트 동작 확인 체크리스트

```bash
docker compose ps                         # 1. backend / frontend / ollama 가 Up 인가
docker compose ps -a | grep ollama-pull   # 2. Exited (0) 인가 (모델 다운로드 완료)
docker compose exec ollama ollama list    # 3. 모델이 목록에 있는가
curl http://localhost:8000/health         # 4. {"status":"ok"}
curl -X POST http://localhost:8000/api/chat \
  -H "Content-Type: application/json" \
  -d '{"prompt":"한국어로 짧게 인사해줘"}'   # 5. 모델 응답이 오는가
# 6. 브라우저에서 http://localhost (EC2 면 http://<EC2_PUBLIC_IP>)
```

> Windows PowerShell 에서는 `curl` 대신 `curl.exe` 를 쓰거나 `Invoke-RestMethod http://localhost:8000/health` 를 사용하세요.
> `grep` 대신 `Select-String` (`docker compose ps -a | Select-String ollama-pull`).

---

## 7. 자주 만나는 에러

| 증상 | 원인 | 해결 |
|------|------|------|
| `Conflict. The container name "/ollama" is already in use` | 다른 프로젝트가 같은 이름(`ollama`) 컨테이너를 이미 사용 중 | `docker ps -a` 로 확인 → 그 컨테이너 `docker stop ollama` 후 `docker rm ollama` (또는 다른 프로젝트 compose 에서 `down`) |
| `Bind for 0.0.0.0:8000 failed: port is already allocated` | 해당 포트를 다른 컨테이너/프로그램이 사용 중 | `docker ps` 로 포트 쓰는 컨테이너 찾아서 정지, 또는 compose 의 포트를 `"8001:8000"` 처럼 변경 |
| `permission denied ... docker.sock` (EC2) | 사용자가 docker 그룹에 아직 반영 안 됨 | `newgrp docker` 또는 SSH 재접속 |
| 백엔드 `502 Ollama request failed` | 모델 다운로드가 아직 안 끝남 / ollama 가 죽음 | `docker compose logs ollama-pull`, `docker compose logs ollama` |
| `Exited (137)` | 메모리 부족(OOM)으로 강제 종료 | `docker stats` 로 확인, 더 작은 모델 사용 또는 인스턴스 사양 업 |
| 코드를 바꿨는데 반영이 안 됨 | 이미지를 다시 빌드하지 않음 | `docker compose up -d --build` |

---

## 8. 한 장 요약

```
docker compose up -d --build   # 띄우기
docker compose ps              # 떠 있나?
docker compose logs -f <svc>   # 왜 안 되지?
docker compose exec <svc> sh   # 안에 들어가 보기
docker compose restart <svc>   # 재시작
docker compose down            # 내리기 (모델 유지)
```
