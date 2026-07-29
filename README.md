# M2 Max Fan Controller

M2 Max MacBook Pro용 네이티브 macOS 메뉴바 팬 컨트롤러입니다. SwiftUI로
작성되었으며 Python이나 외부 런타임이 필요하지 않습니다.

## 현재 검증 상태

- `Mac14,6` M2 Max에서 AppleSMC 연결과 팬 2개의 현재/목표 RPM, 최소/최대
  RPM, 동적 온도 센서 열거를 읽기 전용으로 확인했습니다.
- UI, 커브 계산, IPC, watchdog, 자동 복구 로직은 가짜 하드웨어를 사용한
  자동 테스트와 네이티브 빌드를 통과했습니다.
- 실제 팬 RPM 쓰기는 아직 수행하지 않았습니다. 최초 제어 검증은 사용자의
  명시적 승인 아래 낮은 위험의 짧은 수동 테스트로 진행해야 합니다.

## 요구 사항

- macOS 13 이상
- Apple Silicon Mac
- `/Applications/Xcode.app`의 Xcode 26.6 이상

## 빌드 및 실행

```bash
./script/build_and_run.sh
```

빌드만 검증하고 실행하지 않으려면:

```bash
./script/build_and_run.sh --verify
```

읽기 전용 하드웨어 진단:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcrun swift run FanDiagnostics
```

## 설치 패키지

```bash
./script/build_installer.sh 1.0.0
open installer/FanController-1.0.0.pkg
```

설치 위치는 `/Applications/FanController.app`입니다. 패키지에는 이 앱
번들 하나만 포함됩니다.

로컬 ad-hoc 서명이므로 다른 Mac에서는 Gatekeeper 경고가 나타날 수
있습니다. Apple Developer 계정으로 서명하거나 공증한 배포본이 아닙니다.

## 사용 방식

- 앱 시작 직후에는 관리자 권한 없이 온도와 RPM만 읽습니다.
- `커브` 또는 `수동` 모드를 처음 선택할 때 관리자 암호를 한 번 요청합니다.
- 승인 취소 시 읽기 전용 및 시스템 자동 모드를 유지합니다.
- 활성 세션 동안 앱은 2초마다 helper에 heartbeat를 보냅니다.
- heartbeat가 6초간 끊기거나 센서·쓰기 오류, 잠자기, 앱 종료가 발생하면
  두 팬을 macOS 시스템 자동 모드로 복구합니다.
- `시스템 자동 모드로 즉시 복귀` 버튼은 항상 사용할 수 있습니다.

## 제거

먼저 메뉴에서 시스템 자동 모드로 복귀한 후 앱을 종료합니다.

```bash
sudo rm -rf /Applications/FanController.app
```

이 앱은 LaunchDaemon이나 영구 root helper를 설치하지 않습니다.

## 안전 설계

- UI 프로세스는 AppleSMC 읽기만 직접 수행합니다.
- 관리자 helper는 `status`, `heartbeat`, 팬별 RPM 설정, 시스템 자동 복구,
  종료 명령만 허용합니다.
- IPC에는 임의 SMC 키 쓰기 명령이 없으며 메시지는 16 KiB로 제한됩니다.
- 팬별 하드웨어 범위를 벗어나는 RPM은 쓰기 전에 거부됩니다.
- critical thermal pressure에서는 각 팬의 최대 RPM을 요청합니다.

## 오픈 소스 참고 및 고지

AppleSMC 접근 방식과 Apple Silicon 팬 키 조사는 다음 MIT 프로젝트를
참고했습니다. 각 라이선스 전문은 `LICENSES/`에 포함되어 있습니다.

- [agoodkind/macos-smc-fan](https://github.com/agoodkind/macos-smc-fan)
- [metaspartan/mactop](https://github.com/metaspartan/mactop)
- [angristan/MacThrottle](https://github.com/angristan/MacThrottle)
