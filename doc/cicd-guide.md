# GitHub Actions CI/CD 실습 가이드

직접 따라 치면서 **파이프라인이 도는 걸 눈으로 확인**하는 실습 문서입니다.
명령어는 모두 `D:\TeamProjectToday\TestBuilder` 에서 PowerShell 로 실행합니다.

워크플로 파일: [`.github/workflows/ci-cd.yml`](../.github/workflows/ci-cd.yml)

```
push ──▶ test (pytest) ──▶ build (compose 검사 + 이미지 빌드) ──▶ deploy (EC2, main 만)
```

| 실습 | 하는 것 | 확인할 결과 |
|------|---------|-------------|
| 1 | 저장소 만들고 첫 push | test ✅ build ✅ deploy ⏭ (시크릿 없음 경고) |
| 2 | 테스트 일부러 깨기 | test ❌ → build/deploy 실행 안 됨 |
| 3 | 고쳐서 다시 push | 전부 ✅ |
| 4 | 브랜치 + Pull Request | PR 화면에 체크 표시, deploy 는 안 돔 |
| 5 | 시크릿 등록 → 수동 실행 | deploy ✅ , EC2 에 자동 배포 |
| 6 | 화면 문구 수정 후 push | 브라우저에서 바뀐 화면 확인 |
| 7 | 되돌리기(revert) | 이전 화면으로 자동 복구 |

---

## 실습 0. 준비물 확인

```powershell
git --version
gh --version
gh auth status        # "Logged in to github.com" 이 보여야 함 (안 되면: gh auth login)
```

---

## 실습 1. 저장소 만들고 첫 파이프라인 돌리기

```powershell
git init -b main                  # 이미 했으면 생략
git add -A
git status                        # .venv, .env, *.pem 이 목록에 없는지 확인!
git commit -m "chore: initial commit with CI/CD"

gh repo create TestBuilder --private --source . --remote origin --push
```

바로 실행 상황을 봅니다.

```powershell
gh run list                       # 방금 push 로 생긴 실행 목록
gh run watch                      # 실행 골라서 실시간으로 보기 (끝나면 자동 종료)
gh repo view --web                # 브라우저로 저장소 열기 → Actions 탭
```

**✅ 기대 결과**
- `test` ✅ → `build` ✅ → `deploy` ✅(초록) 이지만 로그에 경고
  `EC2_HOST / EC2_USER / EC2_SSH_KEY 시크릿이 없어 배포를 건너뜁니다.`
- 브라우저 Actions 탭 → **CI/CD** → 실행 클릭 → 각 job 클릭하면 단계별 로그가 보임

---

## 실습 2. 일부러 실패시켜 보기 (CI 가 막아주는지)

`backend/main.py` 의 health 응답을 바꿉니다.

```python
@app.get("/health")
async def health():
    return {"status": "broken"}     # "ok" → "broken"
```

로컬에서 먼저 깨지는지 확인하고 push:

```powershell
cd backend; .\.venv\Scripts\Activate.ps1; pytest -v; deactivate; cd ..
git commit -am "test: break health check on purpose"
git push
gh run watch
```

**❌ 기대 결과**
- `test` 빨간불, `build` / `deploy` 는 **Skipped** → 깨진 코드는 배포되지 않음
- 실패 로그만 모아 보기:

```powershell
gh run view --log-failed
```

`AssertionError: assert {'status': 'broken'} == {'status': 'ok'}` 가 보이면 성공(?)입니다.

---

## 실습 3. 고쳐서 초록불 만들기

`"broken"` → `"ok"` 로 되돌리고:

```powershell
git commit -am "fix: restore health check"
git push
gh run watch
```

**✅ 기대 결과**: 다시 전부 초록. 저장소 첫 화면 커밋 옆에 ✔ 표시.

---

## 실습 4. 브랜치 + Pull Request 흐름 (팀 작업 방식)

```powershell
git switch -c feature/hello-text
```

`frontend/public/index.html` 의 제목을 수정:

```html
<h1>TestBuilder Demo - PR 테스트</h1>
```

```powershell
git commit -am "feat: change title"
git push -u origin feature/hello-text
gh pr create --fill               # PR 생성
gh pr checks --watch              # PR 에 붙은 체크 실시간 확인
```

**✅ 기대 결과**
- PR 화면 하단에 `CI/CD / test`, `CI/CD / build` 체크 ✅
- `deploy` 는 **Skipped** (PR 은 배포 안 함 — 머지 전 검증만)

머지하면 main 에 push 가 일어나서 파이프라인이 다시 돕니다.

```powershell
gh pr merge --squash --delete-branch
git switch main; git pull
gh run watch
```

> (선택) main 보호 규칙: 저장소 Settings → Branches → Add rule → `main` →
> **Require status checks to pass** 에 `test`, `build` 체크 → 테스트 실패한 PR 은 머지 버튼이 막힘.

---

## 실습 5. EC2 자동 배포 켜기

### 5-1. EC2 쪽 준비 (1회)
- [deploy/DEPLOY.md](../deploy/DEPLOY.md) 대로 EC2(Amazon Linux 2023)에서 `deploy/ec2-setup.sh` 실행
  (git, rsync, Docker, compose/buildx 설치 — **rsync 가 없으면 배포 업로드가 실패**하니 이미 docker 를 깔았어도 한 번 실행)
- **보안그룹 인바운드 22번을 `0.0.0.0/0`** 으로 변경
  (GitHub Actions 서버 IP 는 매번 바뀌어서 "내 IP" 만 허용하면 ssh 타임아웃)
- 80번 `0.0.0.0/0` 열려 있는지 확인

### 5-2. 시크릿 등록 (pem 이 있는 폴더의 PowerShell 에서)

```powershell
gh secret set EC2_HOST --repo <GitHub계정>/TestBuilder --body "<EC2_PUBLIC_IP>"
gh secret set EC2_USER --repo <GitHub계정>/TestBuilder --body "ec2-user"
Get-Content .\ec2testkeypair.pem -Raw | gh secret set EC2_SSH_KEY --repo <GitHub계정>/TestBuilder

gh secret list --repo <GitHub계정>/TestBuilder   # 3개 보이면 OK (값은 안 보이는 게 정상)
```

### 5-3. 코드 변경 없이 수동으로 배포 실행

```powershell
cd D:\TeamProjectToday\TestBuilder
gh workflow run ci-cd.yml --ref main
gh run watch
```

**✅ 기대 결과** — `deploy` job 로그 마지막에:

```
{"status":"ok"}
배포 성공
NAME       ... STATUS
backend    ... Up
frontend   ... Up
ollama     ... Up
```

EC2 에서 직접 확인도 해봅니다.

```powershell
ssh -i .\ec2testkeypair.pem ec2-user@<EC2_PUBLIC_IP>
```
```bash
cd ~/TestBuilder && docker compose ps
docker compose logs -f ollama-pull    # 최초 1회 모델 다운로드 (몇 분)
```

브라우저: `http://<EC2_PUBLIC_IP>`

---

## 실습 6. 코드 수정 → push → 화면이 자동으로 바뀌는지

`frontend/public/index.html`:

```html
<h1>TestBuilder Demo - 자동배포 v2</h1>
```

```powershell
git commit -am "feat: v2 title"
git push
gh run watch
```

**✅ 기대 결과**: deploy 끝난 뒤 `http://<EC2_PUBLIC_IP>` 새로고침(Ctrl+F5) → 제목이 `자동배포 v2`.
**ssh 접속도, docker 명령도 직접 치지 않았는데** 서버가 바뀐 것 = CD.

---

## 실습 7. 잘못 배포했을 때 되돌리기

```powershell
git log --oneline -3              # 되돌릴 커밋 해시 확인
git revert --no-edit HEAD         # 마지막 커밋을 취소하는 새 커밋
git push
gh run watch
```

**✅ 기대 결과**: 파이프라인이 다시 돌고, 브라우저 제목이 이전 버전으로 복구.

---

## 자주 쓰는 gh 명령 모음

```powershell
gh run list                       # 최근 실행 목록
gh run watch                      # 실행 중인 것 실시간 보기
gh run view <run-id>              # 실행 요약
gh run view <run-id> --log        # 전체 로그
gh run view --log-failed          # 실패한 단계 로그만
gh run rerun <run-id>             # 전체 재실행
gh run rerun <run-id> --failed    # 실패한 job 만 재실행
gh workflow run ci-cd.yml         # 수동 실행 (workflow_dispatch)
gh pr checks --watch              # PR 체크 상태
gh secret list                    # 시크릿 목록
```

---

## 막혔을 때

| 어디서 | 로그 메시지 | 원인 / 해결 |
|--------|-------------|-------------|
| push | `remote: Permission to ... denied` | `gh auth status` 계정 확인, `gh auth login` |
| test | `ModuleNotFoundError` | 새 패키지를 `requirements.txt` 에 안 넣음 |
| build | `docker compose config` 에러 | compose 들여쓰기/오타 |
| deploy | 경고 `시크릿이 없어 배포를 건너뜁니다` | 실습 5-2 시크릿 등록 |
| deploy | `ssh: connect to host ... timed out` | 보안그룹 22번, EC2 중지/재시작으로 IP 바뀜 → `EC2_HOST` 갱신 |
| deploy | `Permission denied (publickey)` | `EC2_SSH_KEY` 에 pem 전체 내용 들어갔는지, `EC2_USER=ec2-user` |
| deploy | `EC2에 Docker가 없습니다` | EC2 에서 `deploy/ec2-setup.sh` 실행 |
| deploy | `permission denied ... docker.sock` | EC2 에서 `sudo usermod -aG docker ec2-user` 후 재접속 |
| deploy | `헬스체크 실패` | 로그 아래 backend 로그 확인, EC2 메모리 부족(`docker stats`) |
