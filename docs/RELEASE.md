# Sowing 출시 절차

이 문서는 v0.1.0 (MVP) 출시 또는 후속 패치를 준비할 때 따라야 할 단계를 정리합니다.

## 출시 전 체크리스트

### 1. 코드 상태 확인
- [ ] `bundle exec rspec` 전부 통과 (현재 855건)
- [ ] `bundle exec standardrb` 0 issue
- [ ] 5회 연속 stress 통과 (`for i in 1..5; do bundle exec rspec; done`)
- [ ] `bin/sowing-doctor` 환경 점검 통과
- [ ] CHANGELOG.md `[Unreleased]` → `[X.Y.Z] - YYYY-MM-DD` 으로 정리
- [ ] `lib/sowing/version.rb` 의 `VERSION` 갱신

### 2. 의존성 보안 검토
```sh
bundle outdated --strict
bundle audit check --update    # gem-audit
```
주요 보안 이슈가 있으면 패치 후 재테스트.

### 3. 패키징 (W8-T02 ~ T05)

#### Linux (Docker 기반 Tebako)
```sh
./packaging/build.sh linux     # x86_64
./packaging/build.sh linux aarch64
```
산출물: `dist/sowing-${VERSION}-linux-{x86_64,aarch64}`

#### macOS (호스트 직접 빌드)
```sh
./packaging/build.sh macos
# 후속: codesign + notarize (별도)
```

#### Windows (GitHub Actions 또는 VM)
- `packaging/windows/installer.iss` 작성 후 Inno Setup 실행
- (W8-T04 deferred — 별도 작업 필요)

### 4. 패키지 검증
- 각 OS에서 새 사용자 환경(빈 홈 디렉토리)에서 첫 실행 → 온보딩 완료까지 5분 이내
- `bin/sowing-doctor` 실행 → 모든 체크 통과
- 샘플 시드(`rake vault:seed`) → 12건 생성 + 위키링크 그래프 형성 확인

## GitHub Release 절차

### 1. 태그 생성
```sh
git tag -a v0.1.0 -m "v0.1.0 — Sowing MVP"
git push origin v0.1.0
```

### 2. Release 페이지 작성
- GitHub → Releases → New Release
- 태그: `v0.1.0`
- 제목: `v0.1.0 — Sowing MVP`
- 본문: CHANGELOG.md 의 해당 버전 섹션 복사
- 첨부:
  - `dist/sowing-0.1.0-macos-arm64`
  - `dist/sowing-0.1.0-macos-x86_64`
  - `dist/sowing-0.1.0-linux-x86_64`
  - `dist/sowing-0.1.0-linux-aarch64`
  - `dist/sowing-0.1.0-windows-x86_64.exe` (선택)
  - 각 파일의 SHA256 체크섬 (`shasum -a 256`)

### 3. 출시 후 안내
- README.md 의 "Releases 페이지" 링크 점검
- KNOWN_ISSUES.md 갱신 (반드시 — 알려진 한계는 솔직히 공개)
- 베타 테스터에게 다운로드 링크 + 피드백 양식 안내 (W8-T07)

## 핫픽스 절차 (긴급 패치)

1. 이슈 재현 + 테스트 추가 (TDD)
2. 픽스 + spec pass + lint clean
3. CHANGELOG에 `[X.Y.Z+1] - YYYY-MM-DD` 추가
4. version.rb 갱신
5. tag → push → release

## 롤백 절차

신규 버전에 치명적 결함 발견 시:
1. GitHub Release를 "Draft"로 전환 (다운로드 링크 비활성)
2. 이전 버전 Release를 "Latest" 로 재지정
3. 사용자 안내 (CHANGELOG + Release notes에 회수 사유 명시)

## 데이터 호환성 약속

- **마크다운 SoT**: 어떤 버전으로 업그레이드해도 사용자 볼트는 그대로 호환 (CLAUDE.md 원칙 1)
- **DB 스키마 변경**: 마이그레이션으로 자동 처리. 다운그레이드는 보장 안 함 → 출시 전 백업 권장
- **frontmatter 스펙**: ADR-001 준수. 신규 키 추가는 선택적, 기존 키 의미 변경 금지
