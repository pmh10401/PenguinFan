# PenguinFan

[English](README.md) | [한국어](README.ko.md)

PenguinFan은 M2 Max MacBook Pro를 위한 무료 오픈소스 네이티브 macOS 팬
컨트롤러입니다. 가벼운 SwiftUI 메뉴바 UI에서 온도와 팬 RPM을 확인하고,
수동 속도 또는 온도 기반 팬 커브를 사용할 수 있습니다.

> **영원히 무료:** PenguinFan은 [MIT 라이선스](LICENSE)로 무료 배포됩니다.
> 개인 및 상업적 사용, 학습, 수정, 재배포가 가능합니다.

## 실험 버전 안내

`v1.1.0-experimental.1`은 기존 `osascript` 관리자 실행 방식을 제거하고,
서명된 `SMAppService` LaunchDaemon과 권한 분리 XPC 연결을 사용합니다.

이 버전은 다음 조건의 사전 릴리즈입니다.

- `Mac14,6` M2 Max MacBook Pro 한 대에서 실제 검증
- Apple Development 인증서로 서명
- Apple 공증은 받지 않음
- 테스트 목적의 사전 릴리즈

다른 Mac에서는 Gatekeeper가 설치 파일이나 앱 실행을 차단할 수 있습니다.
다운로드를 신뢰하는 경우 **시스템 설정 > 개인정보 보호 및 보안 > 확인 없이
열기**를 사용하세요. 지원되지 않는 하드웨어에서는 진단 결과와 팬 범위를
확인하기 전에 사용하지 마세요.

## 주요 기능

- 네이티브 SwiftUI 메뉴바 앱
- 팬 속도에 따라 움직임이 달라지는 펭귄 메뉴바 아이콘
- 최대 센서 온도 실시간 표시
- 듀얼 팬의 현재 RPM과 목표 RPM 표시
- macOS 시스템 자동 팬 모드
- 온도 기반 커브 모드
- 고정 수동 RPM 모드
- 팬별 하드웨어 범위 검증
- `SMAppService`가 관리하는 root 헬퍼
- 실행 중 코드 신원을 확인하는 권한 XPC 검증
- 서명 식별자, Team ID, 서명 유형을 제한하는 LaunchDaemon
  `SpawnConstraint`
- 6초 하트비트 감시
- macOS 팬 자동 제어 복귀
- 읽기 전용 하드웨어 진단

## 검증 하드웨어 및 결과

현재 사전 릴리즈는 다음 환경에서 검증했습니다.

| 항목 | 값 |
| --- | --- |
| 모델 | `Mac14,6` |
| 칩 | Apple M2 Max |
| Fan 1 범위 | `1350-5349 RPM` |
| Fan 2 범위 | `1522-5777 RPM` |
| 커브 센서 | `TCMz` CPU die hotspot |
| 최소 macOS | macOS 13 |

2026년 7월 30일 실제 하드웨어 Curve 테스트:

- 온도: 약 `78 C`
- 커브 목표: `4873 RPM`
- Fan 1 반응: `4922 RPM`
- Fan 2 반응: `4921 RPM`
- System 모드 복귀: 성공
- 복귀 후 측정값: 약 `1990 / 2158 RPM`
- XPC 검증: `accepted reason=validated`
- 복귀 후 권한 헬퍼 종료 코드: `0`

다른 Apple Silicon 모델은 SMC 키와 팬 범위가 다를 수 있어 현재 지원 대상이
아닙니다.

## 다운로드 및 설치

1. [GitHub Releases](../../releases)에서
   `PenguinFan-Experimental-1.1.0.pkg`를 다운로드합니다.
2. 패키지를 열어 설치를 완료합니다.
3. `/Applications/PenguinFan Experimental.app`을 실행합니다.
4. **커브** 또는 **수동**을 선택하고 권한 안내를 확인한 뒤 **계속**을
   선택합니다.
5. macOS 승인이 필요하면 **시스템 설정 > 일반 > 로그인 항목 및 확장
   프로그램**에서 PenguinFan을 활성화합니다.

온도 모니터링에는 관리자 권한이 필요하지 않습니다. 실제 팬 제어를 요청할
때만 권한 서비스가 실행됩니다.

## 안전 설계

- 헬퍼는 상태, 하트비트, 범위가 제한된 RPM, 복귀, 종료 명령만 처리합니다.
- 실행 중 클라이언트의 경로, 서명 식별자, Team ID, 콘솔 사용자, 설치 경로
  보안을 모두 확인합니다.
- LaunchDaemon은 지정된 서명 헬퍼만 실행합니다.
- 하트비트 손실, 연결 실패, 잠자기, 센서 오류, 앱 종료 또는 System 모드
  선택 시 두 팬을 macOS 자동 제어로 복귀시킵니다.
- macOS thermal pressure가 위험 수준이면 각 팬의 최대 지원 속도를
  요청합니다.

직접 팬 제어는 냉각, 소음, 부품 온도와 하드웨어 수명에 영향을 줄 수
있습니다. 이 소프트웨어는 실험 버전이며 보증 없이 제공됩니다.

## 소스에서 빌드

필요 환경:

- macOS 13 이상
- Apple Silicon Mac
- Swift 6을 지원하는 Xcode

일반 로컬 앱 빌드:

```bash
./script/build_and_run.sh --verify
```

테스트 실행:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcrun swift test
```

읽기 전용 진단 실행:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcrun swift run FanDiagnostics
```

실험용 권한 패키지를 만들려면 유효한 코드 서명 인증서가 필요합니다. 포크를
배포하려면 코드에 고정된 번들 식별자와 Team ID를 자신의 값으로 변경해야
합니다.

## 제거

1. **시스템** 모드를 선택하고 macOS가 팬을 제어하는지 확인합니다.
2. PenguinFan 설정에서 권한 서비스를 제거합니다.
3. PenguinFan을 종료합니다.
4. `/Applications/PenguinFan Experimental.app`을 삭제합니다.

## 참고한 오픈소스

AppleSMC 접근과 Apple Silicon 팬 제어 연구에 다음 프로젝트를
참고했습니다.

- [agoodkind/macos-smc-fan](https://github.com/agoodkind/macos-smc-fan)
- [metaspartan/mactop](https://github.com/metaspartan/mactop)
- [angristan/MacThrottle](https://github.com/angristan/MacThrottle)
- [ryyansafar/MacMonitor](https://github.com/ryyansafar/MacMonitor)

서드파티 고지는 `LICENSES/`에 포함되어 있습니다.

## 라이선스

[MIT 라이선스](LICENSE). 개인 및 상업적 사용 모두 무료입니다.
