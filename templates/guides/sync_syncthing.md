# Syncthing으로 Sowing 볼트 동기화

P2P 동기화 — **클라우드 서버를 거치지 않음**. 데이터가 본인 기기 사이에만 머물러
Sowing의 로컬 우선 철학과 가장 잘 맞음.

## OS 지원 매트릭스

| OS | 지원 | 비고 |
|----|------|------|
| macOS | ✅ | brew install syncthing |
| Windows | ✅ | 인스톨러 또는 Chocolatey |
| Linux | ✅ | apt/dnf 패키지 |
| Android | ✅ | F-Droid / Play Store |
| iOS | ⚠ | 공식 클라이언트 없음 (3rd-party Möbius Sync) |

## 설치

```sh
# macOS
brew install syncthing
brew services start syncthing

# Linux (Debian/Ubuntu)
sudo apt install syncthing
systemctl --user enable --now syncthing

# Windows
choco install syncthing  # 또는 인스톨러
```

설치 후 브라우저에서 `http://localhost:8384` 접속.

## 기기 페어링

1. **기기 A** (예: 데스크톱):
   - "Add Folder" → SowingVault 경로 선택 → Folder ID 메모.
2. **기기 B** (예: 노트북):
   - 같은 네트워크에서 자동 발견. "Add Device"로 A의 ID 추가.
   - A에서 B의 추가 알림 → "Share" 클릭.
   - SowingVault 폴더 동기화 활성화.
3. 양쪽 모두 `SOWING_VAULT` 환경변수가 동일 디렉토리를 가리키도록 설정.

## 검증

- 한쪽에서 빠른 메모 → 5초~30초 내 다른 기기에 반영 (LAN 기준).
- Syncthing UI의 "Out of Sync Items: 0" 확인.

## 주의

- **양쪽이 동시에 켜져 있을 때만** 동기화. 한쪽이 꺼지면 그동안의 변경은 다음 접속 시 일괄 동기화.
- 충돌 시 Syncthing이 `*.sync-conflict-YYYYMMDD-XXXXXX-deviceid.md` 파일을 만듦
  → Sowing의 충돌 다이얼로그(W5-T05)와 별개로 별도 파일로 보존됨. 수동 정리 필요.
- 모바일 동기화는 배터리 소모 — 백그라운드 정책 확인.

## 추가 자료

- [Syncthing 공식](https://syncthing.net/)
- [한글 문서 (커뮤니티)](https://docs.syncthing.net/intro/getting-started.html)
