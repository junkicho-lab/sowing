# iCloud Drive로 Sowing 볼트 동기화

Apple 생태계(맥/아이폰/아이패드)에서 자동 동기화. **macOS·iOS만 지원**.

## OS 지원 매트릭스

| OS | 지원 | 비고 |
|----|------|------|
| macOS | ✅ | 기본 동기화 |
| iOS / iPadOS | ✅ | 옵시디언 모바일과 함께 |
| Windows | ⚠ | iCloud for Windows 설치 필요, 동기화 지연 잦음 |
| Linux | ❌ | 미지원 |

## macOS 설정

1. **시스템 설정 → Apple ID → iCloud → iCloud Drive 켜기**
2. 볼트 폴더를 iCloud Drive 안으로 이동:
   ```sh
   mv ~/Documents/SowingVault ~/Library/Mobile\ Documents/com~apple~CloudDocs/SowingVault
   ```
3. Sowing 실행 시 환경 변수로 새 위치 지정:
   ```sh
   export SOWING_VAULT="$HOME/Library/Mobile Documents/com~apple~CloudDocs/SowingVault"
   ```

## 검증

- 다른 맥에서 같은 Apple ID로 로그인 → `~/Library/Mobile Documents/com~apple~CloudDocs/SowingVault/` 에 파일이 보이면 성공.
- 옵시디언 모바일에서 "iCloud 볼트로 열기" → SowingVault 선택.

## 주의

- iCloud는 **다운로드 시점에 파일을 가져오는** 지연이 있음. 첫 진입 시 잠깐 비어 보일 수 있음 — 잠시 기다리세요.
- `.sowing/` 디렉토리도 함께 동기화됨 — 휴지통·충돌 백업이 모든 기기에 보존됨.
- 충돌 파일(`Conflict copy`)이 발생하면 Sowing의 충돌 처리 화면을 활용해 해결 가능.

## 추가 자료

- [Apple 공식: iCloud Drive 시작하기](https://support.apple.com/ko-kr/guide/icloud/mm6b1a9479/icloud)
