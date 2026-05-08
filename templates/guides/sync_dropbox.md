# Dropbox로 Sowing 볼트 동기화

3-OS 모두 안정적. 무료 2GB로 시작 가능 — 텍스트 위주의 Sowing에는 충분.

## OS 지원 매트릭스

| OS | 지원 | 비고 |
|----|------|------|
| macOS | ✅ | Dropbox.app |
| Windows | ✅ | 기본 클라이언트 |
| Linux | ✅ | 공식 데몬 (deb/rpm) |
| iOS / Android | ✅ | 옵시디언 모바일과 함께 |

## 공통 설정

1. [Dropbox 클라이언트](https://www.dropbox.com/install) 설치 + 로그인.
2. 볼트를 Dropbox 폴더로 이동:
   ```sh
   # macOS / Linux
   mv ~/Documents/SowingVault ~/Dropbox/SowingVault
   export SOWING_VAULT="$HOME/Dropbox/SowingVault"
   ```
   ```cmd
   :: Windows
   move %USERPROFILE%\Documents\SowingVault %USERPROFILE%\Dropbox\SowingVault
   setx SOWING_VAULT "%USERPROFILE%\Dropbox\SowingVault"
   ```
3. Sowing 재시작.

## 선택적 동기화

볼트가 커지면 일부 디렉토리만 로컬에 두기:

- 데스크톱 클라이언트 → 환경설정 → 동기화 → 선택적 동기화
- `.sowing/trash` 같은 백업 디렉토리는 로컬에서 제외 가능 (필요 시에만 fetch)

## 검증

- 다른 기기 Dropbox 폴더에서 SowingVault 확인 → 마크다운 파일 모두 동기화됨.
- 빠른 메모 작성 후 1분 이내 다른 기기에 반영.

## 주의

- Dropbox는 **케이스-민감한 파일명**을 다르게 취급할 수 있음. Sowing은 NFC 정규화 + 슬러그에서 illegal char 제거하므로 일반적으로 안전.
- `.sowing/` 도 함께 동기화됨 (휴지통·충돌 백업 보존). 다른 기기 첫 진입 시 동기화 잠깐 기다리기.
- LAN 동기화 활성화 (환경설정 → 대역폭) → 같은 네트워크 기기 간 빠름.

## 추가 자료

- [Dropbox 도움말 센터](https://help.dropbox.com/ko-kr)
- [선택적 동기화 가이드](https://help.dropbox.com/ko-kr/sync/selective-sync-overview)
