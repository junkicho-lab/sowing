# OneDrive로 Sowing 볼트 동기화

Microsoft 365 사용자에게 안정적. Windows·macOS·iOS·Android 폭넓게 지원.

## OS 지원 매트릭스

| OS | 지원 | 비고 |
|----|------|------|
| Windows | ✅ | 기본 클라이언트 통합 |
| macOS | ✅ | OneDrive.app 설치 |
| iOS / Android | ✅ | OneDrive 모바일 + 옵시디언 |
| Linux | ⚠ | 공식 클라이언트 없음 — `rclone` 또는 `onedrive` (Skilion) 사용 |

## Windows 설정

1. OneDrive 클라이언트 로그인 (Windows 11은 기본 설치).
2. 볼트 폴더를 OneDrive 폴더로 이동:
   ```cmd
   move %USERPROFILE%\Documents\SowingVault %USERPROFILE%\OneDrive\SowingVault
   ```
3. `SOWING_VAULT` 환경변수 설정:
   ```cmd
   setx SOWING_VAULT "%USERPROFILE%\OneDrive\SowingVault"
   ```

## macOS 설정

1. [OneDrive for Mac](https://www.microsoft.com/en-us/microsoft-365/onedrive/download) 설치 + 로그인.
2. 볼트 이동:
   ```sh
   mv ~/Documents/SowingVault ~/OneDrive/SowingVault
   export SOWING_VAULT="$HOME/OneDrive/SowingVault"
   ```

## Linux 설정 (rclone 권장)

```sh
sudo apt install rclone   # 또는 brew install rclone
rclone config             # OneDrive 항목 추가, 인증
mkdir ~/SowingVault
rclone sync onedrive:SowingVault ~/SowingVault
# cron으로 5분마다 sync
```

## 검증

- 다른 기기에서 같은 계정으로 OneDrive 열고 SowingVault 폴더 진입 → 메모/필기/기록 파일 보임.
- 한 곳에서 메모 작성 → 30초~수 분 내 다른 기기에 반영 (네트워크 상태에 따라).

## 주의

- OneDrive 무료는 5GB. Sowing은 텍스트 위주라 충분하지만, 첨부 추가 시 용량 모니터링.
- 한글 파일명: OneDrive는 NFC 정규화. Sowing의 SafeWriter도 NFC라 호환됨.
- 기업/학교 계정은 SharePoint 정책으로 동기화 제한될 수 있음 — IT팀 확인.

## 추가 자료

- [Microsoft 공식 가이드](https://support.microsoft.com/ko-kr/onedrive)
- [rclone OneDrive 문서](https://rclone.org/onedrive/)
