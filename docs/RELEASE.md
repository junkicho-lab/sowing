# Sowing 출시 절차

본 문서는 v0.1.0 (첫 정식 release) 또는 후속 버전 출시 시 따라야 할 단계를
정리합니다. **`.github/workflows/release.yml` 가 대부분 자동화** — 운영자는
태그 push 만 하면 cross-platform artifact + Docker 이미지 + GitHub Release 생성
이 자동 진행됩니다.

## 출시 전 체크리스트

### 1. 코드 상태 확인 (release gate)

```sh
bundle exec rspec | tail -3              # 1332 examples, 0 failures
bundle exec standardrb                    # exit 0
for i in 1 2 3 4 5; do                    # 5x stress
  bundle exec rspec | grep "examples,"
done
bin/sowing-doctor                         # 모든 섹션 ✅
bundle exec rake eval:run                 # 회귀 0 (regressed=false)
bundle exec rake stats:synth_metrics      # (선택) 베타 데이터 있으면
```

### 2. 의존성 보안 검토

```sh
bundle outdated --strict
bundle audit check --update    # gem-audit (별도 설치 시)
```

주요 보안 이슈 발견 시 패치 후 재테스트.

### 3. CHANGELOG / version.rb 정리

- `CHANGELOG.md` 의 `[Unreleased]` 섹션을 새 버전으로 라벨링:
  ```diff
  - ## [Unreleased]
  + ## [0.2.0] - 2026-XX-YY — 변경 요약
  + ## [Unreleased]
  + (다음 릴리스 변경사항 누적용)
  ```
- `lib/sowing/version.rb` 의 `VERSION` 상수 갱신
- 두 파일 commit (예: `[release] v0.2.0 prep — CHANGELOG + version.rb`)

### 4. 베타 마일스톤 평가 (Phase 11/12 출시 시)

수락률 / 통찰 회고 등은 audit.log + 인터뷰로 측정:
```sh
SOWING_SINCE=2026-03-01 SOWING_UNTIL=2026-07-31 \
  bundle exec rake stats:beta_report > beta-report.md
```
결과를 `ROADMAP.md` 의 마일스톤 블록에 기록 후 commit.

## GitHub Release — 자동화 절차 (권장)

`.github/workflows/release.yml` 가 태그 push 시 자동 실행:

### 1. 태그 push

```sh
git tag -a v0.1.0 -m "v0.1.0 — 첫 정식 release"
git push origin v0.1.0
```

### 2. Workflow 자동 진행 (~10분)

GitHub Actions 가 자동으로:

1. **`source-artifacts` job** (3 OS 병렬: macOS / Ubuntu / Windows)
   - Ruby 3.3 setup → bundle install → spec → lint
   - source 패키지 (`tar.gz` for Linux/macOS, `zip` for Windows)
   - SHA256 체크섬 (`*.sha256`)
   - artifact 90일 보관

2. **`docker-image` job** (Ubuntu)
   - Docker 이미지 빌드 (multi-stage)
   - GHCR push (`ghcr.io/junkicho-lab/sowing:0.1.0` + `:latest`)
   - 컨테이너 헬스체크 (`/health` 30초 폴링)

3. **`github-release` job**
   - 모든 artifact 다운로드
   - CHANGELOG 의 해당 버전 섹션 자동 추출 → release notes
   - 4 설치 경로 안내 + SHA256 검증 가이드 자동 추가
   - GitHub Release 생성 + 모든 파일 첨부 + `make_latest: true`

### 3. Workflow 실패 시 수동 개입

GitHub Actions 페이지에서 실패 job 로그 확인. 흔한 원인:
- spec 실패 → 코드 수정 후 새 commit + 태그 재생성 (`git tag -d v0.1.0 && git tag v0.1.0`)
- GHCR 권한 → repo 의 Settings → Actions → "Read and write permissions" 확인
- artifact upload 실패 → retry 가능 (`workflow_dispatch` 로 수동 재실행)

### 4. 출시 후 안내

- [ ] GitHub Release 페이지 확인 — 모든 artifact 정상 업로드
- [ ] Docker 이미지 검증: `docker pull ghcr.io/junkicho-lab/sowing:0.1.0 && docker run -p 48723:48723 ...`
- [ ] `README.md` Releases 링크 점검
- [ ] `KNOWN_ISSUES.md` 갱신 (정직 우선)
- [ ] 베타 테스터·이해관계자에게 release 안내 (`docs/BETA_RECRUITMENT.md` 채널)

## 수동 release (workflow 우회 시)

`workflow_dispatch` 트리거로 수동 실행:
- GitHub → Actions → release → "Run workflow" → tag 입력 (예: `v0.1.0`)

또는 완전 수동:
```sh
# 1. source 패키지 직접 빌드
mkdir -p dist
NAME="sowing-0.1.0-macos"
tar -czf "dist/${NAME}.tar.gz" --exclude='.git' --exclude='.github' .
shasum -a 256 "dist/${NAME}.tar.gz" > "dist/${NAME}.tar.gz.sha256"

# 2. GitHub Release 수동 생성
gh release create v0.1.0 \
  --title "v0.1.0 — 첫 정식 release" \
  --notes-file release-notes.md \
  dist/*.tar.gz dist/*.sha256
```

## 핫픽스 절차 (긴급 패치)

1. 이슈 재현 + 테스트 추가 (TDD)
2. 픽스 + spec pass + lint clean
3. `CHANGELOG.md` 에 새 버전 섹션 추가 (예: `[0.1.1] - YYYY-MM-DD`)
4. `lib/sowing/version.rb` 의 PATCH 증가
5. commit → tag → push (workflow 자동 진행)

## 롤백 절차

신규 버전에 치명적 결함 발견 시:

1. GitHub Release 를 "Draft" 로 전환 (다운로드 링크 비활성)
2. 이전 버전 Release 를 "Latest" 로 재지정
3. Docker 이미지 `:latest` 태그를 이전 버전으로 재push:
   ```sh
   docker pull ghcr.io/junkicho-lab/sowing:0.1.0
   docker tag ghcr.io/junkicho-lab/sowing:0.1.0 ghcr.io/junkicho-lab/sowing:latest
   docker push ghcr.io/junkicho-lab/sowing:latest
   ```
4. 사용자 안내 (`CHANGELOG.md` + Release notes 에 회수 사유 명시)
5. 핫픽스 진행 → 새 patch release

## 데이터 호환성 약속

- **마크다운 SoT**: 어떤 버전으로 업그레이드해도 사용자 vault 그대로 호환 (CLAUDE.md 원칙 1)
- **DB 스키마 변경**: 마이그레이션 자동. 다운그레이드 보장 안 함 → 출시 전 vault 백업 권장 (volume snapshot 또는 `cp -r vault/ vault-backup-$(date +%Y%m%d)/`)
- **frontmatter 스펙**: ADR-001 준수. 신규 키 추가는 선택적, 기존 키 의미 변경 금지
- **MCP API**: Phase 9 의 12 도구 schema 변경 없음 보장. 새 도구 추가만 허용 (additive).
- **합성기 frontmatter**: `is_synth: true` 보장. type 별 추가 키 (synth_target / synth_at 등) 후방 호환.

## 외부 리소스 필요한 정식 인스톨러 (deferred)

본 release 자동화는 *signing 없는* source artifact + Docker 이미지만 생성.
정식 OS 인스톨러는 외부 리소스 확보 후 별도 워크플로우 추가:

- **macOS DMG** (W8-T03): Apple Developer 계정 ($99/년) → codesign + notarize
- **Windows MSI** (W8-T04): Inno Setup + (선택) Authenticode 인증서
- **Linux AppImage** (W8-T05): linuxdeploy + 우분투 22.04 검증

각 작업 진입 시 `.github/workflows/release-installers.yml` 별도 추가 권장.
