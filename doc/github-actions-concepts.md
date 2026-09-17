# CI/CD 와 GitHub Actions 개념 학습

> 목표: "push 하면 **어디서, 무엇이, 어떤 순서로** 실행되는지" 머릿속에 그림이 그려지게 만들기.
> 이 저장소의 실제 파일 [`.github/workflows/ci-cd.yml`](../.github/workflows/ci-cd.yml) 을 교재로 씁니다.
> 직접 따라 하는 실습은 [cicd-guide.md](cicd-guide.md) 에 있습니다.

**학습 순서**
1. CI/CD 가 뭔지 (왜 필요한지)
2. GitHub Actions 의 6가지 구성요소
3. push 한 순간부터 끝날 때까지 실제로 벌어지는 일
4. 우리 `ci-cd.yml` 한 줄씩 읽기
5. 헷갈리는 포인트
6. 손으로 만져보는 미니 실습
7. 셀프 퀴즈

---

## 1. CI/CD 란?

### 1-1. 없을 때 vs 있을 때

**없을 때 (수동)**
```
코드 수정 → (테스트 깜빡함) → ssh 접속 → git pull → docker compose up --build
         → 서버에서 에러 → 다시 로컬 수정 → 또 ssh ...
```
- 사람이 매번 같은 절차를 반복 → 빼먹고, 실수하고, 누가 언제 배포했는지 모름

**있을 때 (자동)**
```
코드 수정 → git push → (끝)
                        └ GitHub 이 알아서: 테스트 → 빌드 → 서버 배포 → 결과 알림
```

### 1-2. 용어

| 용어 | 뜻 | 이 프로젝트에서 |
|------|----|-----------------|
| **CI** (Continuous Integration, 지속적 통합) | 코드를 올릴 때마다 **자동으로 테스트·빌드**해서 "합쳐도 안 깨지는지" 검증 | `test` job, `build` job |
| **CD** (Continuous Delivery, 지속적 제공) | 검증된 코드를 **언제든 배포 가능한 상태**로 만들어 둠 (배포 버튼은 사람이) | `workflow_dispatch` 수동 실행 |
| **CD** (Continuous Deployment, 지속적 배포) | 검증 통과하면 **사람 개입 없이 서버까지 자동 배포** | main push 시 `deploy` job |

> 한 줄 요약: **CI = 검사**, **CD = 배달**.

### 1-3. 공장 비유

```
[원재료 입고]   [품질검사]    [포장]        [배송]
  git push  →  test(pytest) → build(이미지) → deploy(EC2)
                  │
                  └ 불량이면 여기서 라인 정지 → 뒤 공정 실행 안 함
```

---

## 2. GitHub Actions 구성요소 6가지

```
Workflow (ci-cd.yml 파일 하나)
 ├─ on: Event ─────────────── "언제 실행?"      push, pull_request, 수동 실행 ...
 └─ jobs:
     ├─ Job: test ──────────── "무슨 작업?"      runs-on: ubuntu-latest  ← Runner (어디서?)
     │   ├─ Step: uses: actions/checkout@v4     ← Action (남이 만든 부품)
     │   ├─ Step: uses: actions/setup-python@v5
     │   ├─ Step: run: pip install ...          ← 쉘 명령
     │   └─ Step: run: pytest -v
     ├─ Job: build   (needs: test)
     └─ Job: deploy  (needs: build)  ← ${{ secrets.EC2_SSH_KEY }}  ← Secret (비밀값)
```

| 구성요소 | 설명 | 비유 |
|----------|------|------|
| **Workflow** | `.github/workflows/*.yml` 파일 하나. 자동화 전체 시나리오 | 레시피 한 장 |
| **Event** (`on:`) | 워크플로를 깨우는 트리거 | 주문이 들어옴 |
| **Job** | 한 대의 컴퓨터(Runner)에서 실행되는 작업 묶음 | 요리사 한 명 |
| **Step** | Job 안에서 **위에서 아래로 순서대로** 실행되는 한 단계 | 레시피의 한 줄 |
| **Runner** | Job 을 실제로 실행하는 **GitHub 이 빌려주는 가상머신** | 주방 |
| **Action** (`uses:`) | 재사용 가능한 Step 부품 (마켓플레이스) | 밀키트 |
| **Secret** | 비밀번호·키 같은 값. 로그에 `***` 로 가려짐 | 금고 |

### Step 의 두 종류

```yaml
- uses: actions/checkout@v4      # (1) 남이 만든 Action 가져다 쓰기
- run: pytest -v                 # (2) 쉘 명령 직접 실행
```

---

## 3. push 한 순간부터 벌어지는 일 (가장 중요)

```
 내 PC                     GitHub                           GitHub Runner (임시 VM)            EC2
───────                  ────────                          ──────────────────────             ─────
git push ─────────────▶ 코드 저장
                         │
                         ├ .github/workflows/*.yml 탐색
                         ├ "on: push, branches: main" 일치!
                         │
                         ├ test job 용 VM 생성 ─────────▶ [빈 Ubuntu 컴퓨터 부팅]
                         │                                 checkout (코드 복사해옴)
                         │                                 python 설치, pip install
                         │                                 pytest
                         │                  ◀─ 성공 ────── [VM 삭제 🗑]
                         │
                         ├ build job 용 VM 생성 ────────▶ [또 새 빈 컴퓨터]
                         │                                 checkout (다시!)
                         │                                 docker compose build
                         │                  ◀─ 성공 ────── [VM 삭제 🗑]
                         │
                         ├ deploy job 용 VM 생성 ───────▶ [또 새 빈 컴퓨터]
                         │                                 checkout
                         │                                 pem 키를 파일로 저장
                         │                                 rsync ────────────────────────▶ ~/TestBuilder 갱신
                         │                                 ssh "docker compose up" ──────▶ 컨테이너 재시작
                         │                                                                  health 체크 OK
                         │                  ◀─ 성공 ────── [VM 삭제 🗑]
                         │
                         └ Actions 탭에 ✅ 표시, 커밋 옆에 ✔
```

### 여기서 꼭 이해할 3가지

**① Runner 는 매번 "완전히 빈" 컴퓨터다**
- 내 PC 도, EC2 도 아닌 **GitHub 데이터센터의 일회용 VM**
- 그래서 모든 job 이 `actions/checkout` 으로 **코드를 먼저 가져와야** 함 (안 하면 폴더가 비어있음)
- Python, 패키지도 매번 새로 설치 (그래서 `cache: pip` 로 속도 개선)

**② Job 끼리는 컴퓨터가 다르다**
- `test` 에서 설치한 패키지는 `build` 에 없음. 파일도 공유 안 됨
- 기본은 **병렬 실행** → `needs:` 를 써야 **순서대로** 실행됨

**③ EC2 에는 Runner 가 "밖에서" 접속한다**
- EC2 입장에서는 "모르는 IP 가 ssh 로 들어옴" → 그래서
  - pem 키가 필요 (→ Secret `EC2_SSH_KEY`)
  - 보안그룹 22번이 GitHub IP 에 열려 있어야 함 (IP 가 매번 바뀌어서 `0.0.0.0/0`)
- **EC2 에 git clone 이 필수가 아닌 이유**: Runner 가 checkout 한 코드를 rsync 로 직접 밀어넣기 때문

---

## 4. 우리 `ci-cd.yml` 한 줄씩 읽기

### 4-1. 이름과 트리거

```yaml
name: CI/CD                  # Actions 탭에 보이는 이름

on:                          # ── 언제 실행?
  push:
    branches: [main]         # main 에 push 될 때
  pull_request:
    branches: [main]         # main 으로 향하는 PR 이 열리거나 커밋이 추가될 때
  workflow_dispatch:         # Actions 탭의 "Run workflow" 버튼 (수동)
```

> `feature/abc` 브랜치에 push 만 하면? → `on.push.branches` 에 없으므로 **실행 안 됨**. PR 을 열어야 실행.

```yaml
concurrency:
  group: ci-cd-${{ github.ref }}   # 같은 브랜치의 실행은 한 그룹
  cancel-in-progress: false        # 앞 실행이 끝날 때까지 뒤 실행은 대기 (배포 겹침 방지)
```

### 4-2. test job — CI

```yaml
jobs:
  test:                              # job ID (다른 job 이 needs 로 참조하는 이름)
    runs-on: ubuntu-latest           # Runner 종류
    defaults:
      run:
        working-directory: backend   # 이 job 의 모든 run 은 backend/ 에서 실행
    steps:
      - uses: actions/checkout@v4    # ① 저장소 코드를 Runner 로 복사

      - uses: actions/setup-python@v5
        with:                        # Action 에 넘기는 입력값
          python-version: "3.11"     # Dockerfile 과 같은 버전으로 맞춤
          cache: pip                 # 다음 실행 때 pip 다운로드 재사용

      - name: Install dependencies   # 로그에 보일 이름
        run: pip install -r requirements.txt -r requirements-dev.txt

      - name: Run pytest
        run: pytest -v               # 종료코드 ≠ 0 이면 Step 실패 → Job 실패
```

> **실패 판정 규칙**: `run` 명령의 **종료 코드(exit code)가 0 이 아니면 실패**. pytest 는 테스트가 하나라도 실패하면 1 을 반환 → job ❌.

### 4-3. build job — CI

```yaml
  build:
    runs-on: ubuntu-latest
    needs: test                      # test 가 성공해야 시작. 실패하면 Skipped
    steps:
      - uses: actions/checkout@v4    # 새 VM 이니까 또 checkout
      - name: Prepare .env
        run: cp .env.example .env
      - name: Validate docker-compose.yml
        run: docker compose config --quiet    # 문법 오류면 실패
      - name: Build images
        run: docker compose build backend frontend   # Dockerfile 이 깨졌으면 실패
```

> Runner(ubuntu-latest)에는 Docker 가 **기본 설치**돼 있어서 바로 쓸 수 있습니다.

### 4-4. deploy job — CD

```yaml
  deploy:
    runs-on: ubuntu-latest
    needs: build
    if: github.event_name != 'pull_request' && github.ref == 'refs/heads/main'
    #   └ PR 이 아니고, main 브랜치일 때만. (PR 은 검사만 하고 배포는 안 함)
    env:                                         # 이 job 에서 쓸 환경변수
      EC2_HOST: ${{ secrets.EC2_HOST }}          # ${{ }} = GitHub 표현식
      EC2_USER: ${{ secrets.EC2_USER }}
      EC2_SSH_KEY: ${{ secrets.EC2_SSH_KEY }}
      APP_DIR: TestBuilder
```

**Step 1: 시크릿 확인 → 출력값(output) 만들기**
```yaml
      - name: Check secrets
        id: check                                # 다른 step 이 참조할 ID
        run: |
          if [ -z "$EC2_HOST" ] ...; then
            echo "::warning::시크릿이 없어 배포를 건너뜁니다."   # Actions 화면에 노란 경고
            echo "ready=false" >> "$GITHUB_OUTPUT"            # step 출력값 저장
          else
            echo "ready=true" >> "$GITHUB_OUTPUT"
          fi
```

**Step 2~: 출력값으로 조건 실행**
```yaml
      - uses: actions/checkout@v4
        if: steps.check.outputs.ready == 'true'  # 위 step 의 출력값 읽기
```

**SSH 키 준비 → 파일 업로드 → 원격 실행**
```yaml
      - name: Setup SSH key
        run: |
          echo "$EC2_SSH_KEY" > ~/.ssh/ec2.pem            # Secret → 파일
          chmod 600 ~/.ssh/ec2.pem
          ssh-keyscan -H "$EC2_HOST" >> ~/.ssh/known_hosts # "yes/no" 질문 미리 처리

      - name: Upload project files (rsync)
        run: rsync -az --delete --exclude '.env' ... ./ "$EC2_USER@$EC2_HOST:~/$APP_DIR/"
        #    Runner 의 코드 → EC2 로 복사. 서버의 .env 는 보호

      - name: docker compose up on EC2
        run: |
          ssh ... bash -s <<'EOF'        # EOF 사이 명령이 EC2 에서 실행됨
          docker compose up -d --build
          curl http://localhost:8000/health   # 헬스체크 실패 → exit 1 → job ❌
          EOF

      - name: Cleanup SSH key
        if: always()                     # 앞 step 이 실패해도 무조건 실행
        run: rm -f ~/.ssh/ec2.pem
```

### 4-5. 실행 조건 한눈에 보기

```
                 test ──needs──▶ build ──needs──▶ deploy
                                                   if: main push/수동
push main         ✅             ✅               ✅ (시크릿 있으면 실제 배포)
PR → main         ✅             ✅               ⏭ Skipped
test 실패          ❌             ⏭ Skipped        ⏭ Skipped
```

---

## 5. 헷갈리는 포인트 Q&A

**Q. Actions 는 내 EC2 에서 실행되나요?**
A. 아니요. GitHub 의 임시 VM(Runner)에서 실행되고, deploy 단계에서만 ssh 로 EC2 에 **원격 접속**해 명령을 보냅니다.

**Q. 그럼 EC2 에 git clone 은 해야 하나요?**
A. CI/CD 를 쓰면 **필수 아님**. Runner 가 rsync 로 파일을 넣어줍니다. EC2 에서 한 번 필요한 건 `ec2-setup.sh` (Docker 설치) 뿐입니다.
수동으로 clone 해서 쓰고 싶다면 주소는 `https://github.com/Lui02372/TestBuilder.git` 이 맞고,
private 저장소라 **비밀번호 자리에 Personal Access Token** 을 넣어야 합니다.

**Q. `${{ }}` 와 `$VAR` 차이는?**

| 문법 | 누가 해석? | 언제? | 예 |
|------|-----------|-------|----|
| `${{ secrets.X }}`, `${{ github.ref }}` | **GitHub** | 명령 실행 **전**에 값으로 치환 | `if:`, `env:`, `with:` |
| `$EC2_HOST` | **쉘(bash)** | 명령 실행 **중** | `run:` 안 |

**Q. Secret 은 로그에 보이나요?**
A. `***` 로 가려집니다. 또 **Fork 된 저장소의 PR** 에는 전달되지 않아 외부인이 훔칠 수 없습니다.

**Q. 워크플로 파일을 수정하면?**
A. 그 커밋을 push 하는 순간 **수정된 버전으로** 실행됩니다. (워크플로도 코드입니다)

**Q. 돈이 드나요?**
A. public 저장소는 무료, private 은 월 무료 사용량(분 단위)이 있고 이 프로젝트는 1회 약 1분이라 충분합니다.

---

## 6. 미니 실습 — 개념을 손으로 확인하기

`.github/workflows/playground.yml` 을 새로 만들고 push 해보세요. (수동 실행 전용이라 기존 CI/CD 와 안 겹칩니다)

```yaml
name: Playground

on:
  workflow_dispatch:
    inputs:
      who:
        description: "인사할 이름"
        default: "TestBuilder"

jobs:
  # 실습 A: Runner 는 빈 컴퓨터다
  explore:
    runs-on: ubuntu-latest
    steps:
      - name: checkout 전 - 폴더가 비어있음
        run: ls -la

      - uses: actions/checkout@v4

      - name: checkout 후 - 코드가 생김
        run: ls -la

      - name: Runner 정보
        run: |
          echo "OS: $(uname -a)"
          echo "Python: $(python3 --version)"
          echo "Docker: $(docker --version)"
          echo "CPU: $(nproc) cores"

  # 실습 B: 컨텍스트(${{ }}) 값 보기
  context:
    runs-on: ubuntu-latest
    steps:
      - run: |
          echo "이벤트:   ${{ github.event_name }}"
          echo "브랜치:   ${{ github.ref }}"
          echo "커밋:     ${{ github.sha }}"
          echo "실행한 사람: ${{ github.actor }}"
          echo "입력값:   ${{ inputs.who }}"

  # 실습 C: job 사이 순서(needs)와 값 전달(outputs)
  make-value:
    runs-on: ubuntu-latest
    outputs:
      lucky: ${{ steps.pick.outputs.number }}
    steps:
      - id: pick
        run: echo "number=$((RANDOM % 100))" >> "$GITHUB_OUTPUT"

  use-value:
    runs-on: ubuntu-latest
    needs: make-value
    steps:
      - run: echo "앞 job 이 뽑은 숫자 = ${{ needs.make-value.outputs.lucky }}"

  # 실습 D: 실패와 always()
  fail-demo:
    runs-on: ubuntu-latest
    steps:
      - run: echo "1단계 OK"
      - run: exit 1                       # 일부러 실패
      - run: echo "나는 실행 안 됨"
      - if: always()
        run: echo "나는 always() 라서 실행됨"
```

실행:

```powershell
git add .github/workflows/playground.yml
git commit -m "chore: add actions playground"
git push                                   # ← push 해도 on 에 push 가 없어서 Playground 는 안 돎
gh workflow run playground.yml -f who=철수   # 수동 실행
gh run watch
```

**관찰 포인트 체크리스트**
- [ ] A: 첫 `ls -la` 는 비어 있고, checkout 후에야 파일이 보인다 → **Runner 는 빈 컴퓨터**
- [ ] A: Docker, Python 이 이미 깔려 있다 → **ubuntu-latest 기본 도구**
- [ ] B: `github.event_name` 이 `workflow_dispatch` 로 찍힌다
- [ ] 화면의 job 그래프에서 `explore`, `context`, `make-value`, `fail-demo` 는 **동시에** 시작, `use-value` 만 **나중에** 시작 → **needs 가 순서를 만든다**
- [ ] C: 앞 job 의 숫자가 뒤 job 에 전달된다 → **outputs**
- [ ] D: `exit 1` 뒤 step 은 회색(skipped), `always()` step 만 실행 → **실패 규칙**
- [ ] 전체 실행 결과는 ❌ (fail-demo 때문) — 일부러 그런 것

다 봤으면 `fail-demo` job 을 지우거나 파일 자체를 삭제하세요.

---

## 7. 셀프 퀴즈

<details>
<summary>1. build job 에서 <code>actions/checkout</code> 을 빼면 어떻게 될까?</summary>

`docker compose config` 에서 `no configuration file provided` 에러로 실패. Job 마다 새 VM 이라 코드가 없음.
</details>

<details>
<summary>2. feature 브랜치에 push 만 했는데 Actions 가 안 돈다. 왜?</summary>

`on.push.branches: [main]` 이라 main 만 트리거. PR 을 main 으로 열면 `pull_request` 이벤트로 test/build 실행.
</details>

<details>
<summary>3. PR 에서 deploy 가 Skipped 인 이유는?</summary>

`if: github.event_name != 'pull_request' && ...` 조건. 머지 전 코드는 검증만 하고 서버에 올리지 않기 위해.
</details>

<details>
<summary>4. deploy 에서 <code>ssh: connect to host ... timed out</code>. 가장 먼저 볼 곳은?</summary>

EC2 보안그룹 22번 인바운드. "내 IP" 로만 열려 있으면 GitHub Runner IP 가 막힘. 그다음 EC2 재시작으로 퍼블릭 IP 가 바뀌었는지(`EC2_HOST`).
</details>

<details>
<summary>5. <code>needs: test</code> 를 build 에서 지우면?</summary>

test 와 build 가 동시에 시작. 테스트가 실패해도 build 는 계속 돌고, deploy 는 build 만 기다리므로 **깨진 코드가 배포될 수 있음**.
</details>

<details>
<summary>6. Secret 값을 <code>run: echo ${{ secrets.EC2_SSH_KEY }}</code> 로 찍으면 보일까?</summary>

로그에는 `***` 로 마스킹됨. 그래도 이런 코드는 쓰지 않는 게 원칙 (변형된 값은 마스킹이 안 될 수 있음).
</details>

<details>
<summary>7. 서버의 <code>.env</code> 에 모델을 바꿔 뒀는데 배포 후에도 유지되는 이유는?</summary>

rsync 에 `--exclude '.env'` 가 있어 덮어쓰지도 삭제하지도 않음. 원격 스크립트도 `.env` 가 없을 때만 복사.
</details>

---

## 용어 사전

| 용어 | 한 줄 설명 |
|------|-----------|
| Workflow | `.github/workflows/*.yml` 한 파일 |
| Event / Trigger | 워크플로를 시작시키는 사건 (`push`, `pull_request`, `workflow_dispatch`, `schedule`) |
| Job | Runner 1대에서 실행되는 step 묶음. 기본 병렬 |
| Step | job 안의 순차 실행 단위 (`uses` 또는 `run`) |
| Runner | job 을 실행하는 VM (`ubuntu-latest` = GitHub 호스팅) |
| Action | 재사용 가능한 step (`owner/repo@version`) |
| `needs` | job 실행 순서/의존성 |
| `if` | 조건부 실행 |
| `with` | action 에 넘기는 입력 |
| `env` | 환경변수 |
| `secrets` | 암호화 저장된 비밀값 (Settings → Secrets) |
| Context | `github`, `secrets`, `steps`, `needs`, `inputs` 등 `${{ }}` 안에서 쓰는 객체 |
| `$GITHUB_OUTPUT` | step 출력값을 저장하는 파일 |
| `::warning::` | 로그에서 화면 경고로 표시하는 특수 명령 |
| Run | 워크플로가 한 번 실행된 기록 (Actions 탭의 한 줄) |
