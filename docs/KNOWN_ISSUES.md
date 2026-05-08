# 알려진 이슈 / 한계

이 문서는 v0.1.0 시점의 솔직한 한계를 정리합니다. 사용자가 사전에 인지하고
필요 시 우회할 수 있도록 합니다.

## 패키징 / 배포

| 항목 | 상태 | 우회 방법 |
|------|------|-----------|
| macOS DMG + codesign + notarize | ⏳ 미구현 | 소스에서 빌드 (`bundle install && bin/sowing dev`) |
| Windows Inno Setup 인스톨러 | ⏳ 미구현 | WSL2에서 Linux 빌드 사용 |
| Linux AppImage 자동 생성 | ⏳ 미구현 | Docker 빌드(`./packaging/build.sh linux`) |
| 시스템 트레이 wrapper | ⏳ 비-필수 | 브라우저로 `http://127.0.0.1:48723` 사용 |
| 자동 업데이트 | ❌ 없음 | GitHub Releases 에서 수동 다운로드 |

## 기능 한계

### 검색
- **2글자 한국어 검색**: FTS5 trigram은 3+자만 매칭. 2자는 LIKE 폴백으로 대응하지만 5,000건 이상에서 느려질 수 있음
- **퍼지 검색 / 동의어**: 미지원. 정확한 키워드 필요

### 동기화
- **외부 충돌 자동 머지 불가**: 동시 편집 발생 시 사용자가 Keep Mine / Keep Theirs 직접 선택 (자동 3-way merge 없음)
- **모바일**: 옵시디언 모바일을 통한 "보기"는 가능. Sowing UI 자체의 모바일 대응은 W9+ 작업
- **iOS Syncthing**: 공식 클라이언트 없음 (3rd-party Möbius Sync 사용)

### 통계
- **장기 추세**: 일별 통계만 집계. 주별/월별 트렌드 차트는 W9+ (Phase 2)
- **시간대 변경 시**: KST 고정. 사용자가 다른 시간대로 이주하면 과거 일자 재집계 필요

### UI
- **단축키 사용자 정의**: 미지원 (Cmd+K, Cmd+Shift+M 고정)
- **다크 모드**: 미지원 (W9+ 우선순위 P1)
- **언어**: 한국어만 (i18n 인프라는 r18n-core로 갖춤, 번역은 추후)

### 위키링크
- **별칭 alias 매칭 한계**: `[[target|alias]]`의 alias는 본문 표시용. 매칭은 target 으로만
- **부분 매칭**: 정확 title 매칭만. 비슷한 이름은 broken으로 표시

## 보안 / 개인정보

- **암호화**: 마크다운 파일은 평문 저장. 디스크 암호화(FileVault, BitLocker)는 OS 차원에서 활성화 권장
- **클라우드 동기화**: 선택한 서비스(iCloud/OneDrive/Dropbox)의 보안 정책에 의존
- **CSRF 토큰**: Sinatra 기본. 추가 강화는 W9+
- **외부 link**: 마크다운 링크는 `target="_blank"` + `rel="noopener noreferrer"` 자동 적용 안 함 (commonmarker 기본 동작)

## 성능

- **5,000건 검색**: < 500ms (W4-T02 검증). 그 이상에서는 미테스트
- **10,000건 자동완성**: < 100ms (W3-T03 검증)
- **메모 100건 페이지**: < 200ms (W2-T03 검증)
- **첨부 (이미지·PDF)**: 미지원. 마크다운 텍스트만

## 데이터 복구

- **휴지통**: `vault/.sowing/trash` 에 영구 보존 (수동 정리 필요)
- **충돌 백업**: `vault/.sowing/conflicts/{path}/{base}.{ts}.md` 에 보존
- **자동 백업**: 미지원. 클라우드 동기화 또는 수동 zip 권장
- **Time Machine 등 OS 백업**: 마크다운 파일이라 표준 백업 도구 모두 호환

## 운영

- **로그**: `data_dir/sowing.log` 에 기록 (회전 미구현 — 수동 정리)
- **메트릭**: 없음. 사용 통계는 dashboard 에서 사용자가 직접 확인
- **원격 진단**: 없음. 문제 시 `bin/sowing-doctor` 실행 결과를 공유

## 베타 사용자에게

상기 한계 중 일부는 **의도적인 단순화**입니다 (CLAUDE.md 원칙: KISS, YAGNI).
사용 중 불편한 점이 있으면 GitHub Issues 로 알려주세요 — 우선순위에 반영합니다.
