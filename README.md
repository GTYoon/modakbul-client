# 모닥불 Season 1 클라이언트 배포 저장소

Minecraft 1.21.1 · Fabric Loader 0.19.3 기반 전용 클라이언트의 자동 업데이트 파일입니다.

- 서버: `116.126.112.66:25565`
- 런처 배포표: `distribution.json`
- 보조 업데이터 목록: `manifest.json`
- 전용 런처 소스: [GTYoon/modakbul-launcher](https://github.com/GTYoon/modakbul-launcher)

전용 런처는 `distribution.json`의 크기와 MD5를 검사해 필요한 파일만 받습니다. 기존 클라이언트에 포함된 보조 업데이터는 `manifest.json`의 SHA-256을 검사합니다.

GitHub 저장소의 단일 파일 100MB 제한을 넘는 파일은 `client-v1.0.0` Release 자산에서 받도록 분리되어 있습니다. 게임 안에서는 원래 파일명과 경로로 설치됩니다.

## 운영자용 재생성

현재 서버와 기준 클라이언트를 반영한 전체 재생성 도구는 `tools/build-modakbul-client.ps1`입니다. 이 스크립트는 다음 항목을 함께 생성하고 검증합니다.

- Modrinth `.mrpack`
- CurseForge 호환 ZIP
- Helios `distribution.json`
- 보조 업데이터 `manifest.json`
- GitHub Release로 올릴 100MB 초과 파일

플레이어 데이터와 서버 월드는 이 저장소에 포함되지 않습니다.
