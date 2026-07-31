# PenguinFan

[English](README.md) | [한국어](README.ko.md)

PenguinFan은 M2 Max MacBook Pro를 위한 무료 오픈소스 네이티브 macOS 팬
컨트롤러입니다. 가벼운 SwiftUI 메뉴바 UI에서 온도와 듀얼 팬 RPM을 확인하고,
온도 커브 또는 수동 RPM을 적용한 뒤 macOS 자동 제어로 즉시 복귀할 수 있습니다.

> **영원히 무료:** PenguinFan은 [MIT 라이선스](LICENSE)로 무료 배포됩니다.
> 개인 및 상업적 사용, 학습, 수정, 재배포가 가능합니다.

## PenguinFan 1.2.2 정식 릴리즈

`1.2.2`는 설치 후 커브와 수동 제어가 안정적으로 동작하도록 보완한 릴리즈입니다.
로컬라이즈드 및 심볼릭 링크 앱 경로를 지원하고, 앱 업데이트 중 승인된
`SMAppService` 헬퍼 권한을 유지하며, 짧은 온도 측정 공백에서도 커브 명령을
안정적으로 유지합니다.

- 정식 앱: `/Applications/PenguinFan.app`
- 설치 파일: `PenguinFan-1.2.2.pkg`
- Apple Development 인증서로 서명
- `Mac14,6` M2 Max MacBook Pro에서 실제 검증
- Apple 공증은 아직 받지 않음

다른 Mac에서는 Gatekeeper가 설치 파일이나 앱 실행을 차단할 수 있습니다.
다운로드를 신뢰하는 경우 **시스템 설정 > 개인정보 보호 및 보안 > 확인 없이
열기**를 사용하세요. 현재 실제 하드웨어 검증 범위는 아래 모델로 제한됩니다.

## 주요 기능

- 네이티브 SwiftUI 메뉴바 앱
- 팬 속도에 따라 걷는 속도가 달라지는 펭귄 아이콘
- 최대 센서 온도 실시간 표시
- 듀얼 팬의 현재 RPM과 목표 RPM 표시
- macOS 시스템, 온도 커브, 고정 수동 모드
- 첫 커브 포인트 미만에서 macOS 시스템 팬 제어 사용
- 수동 RPM 직접 입력, 슬라이더, `-50` / `+50` 버튼
- 팬별 하드웨어 RPM 범위 검증
- `SMAppService`가 관리하는 root 헬퍼
- 코드 신원과 설치 경로를 확인하는 권한 XPC 검증
- 서명 식별자, Team ID, 서명 유형을 제한하는 `SpawnConstraint`
- 6초 하트비트 watchdog
- macOS 팬 자동 제어 복귀
- 읽기 전용 하드웨어 진단

## 검증 하드웨어 및 결과

| 항목 | 값 |
| --- | --- |
| 모델 | `Mac14,6` |
| 칩 | Apple M2 Max |
| Fan 1 범위 | `1350-5349 RPM` |
| Fan 2 범위 | `1522-5777 RPM` |
| 커브 센서 | `TCMz` CPU die hotspot |
| 최소 macOS | macOS 13 |

2026년 7월 31일 실제 하드웨어 Curve 테스트 결과:

- 온도: 약 `81.5 C`
- 커브 목표: `5063 RPM`
- Fan 1 반응: `5065 RPM`
- Fan 2 반응: `5048 RPM`
- XPC 검증: `accepted reason=validated`
- 권한 헬퍼: 실행 중이며 Curve 명령 수락 확인

다른 Apple Silicon 모델은 SMC 키와 팬 범위가 다를 수 있어 현재 지원 대상이
아닙니다.

## 다운로드 및 설치

1. [GitHub Releases](../../releases)에서 `PenguinFan-1.2.2.pkg`를 받습니다.
2. 패키지를 열어 설치합니다.
3. `/Applications/PenguinFan.app`을 실행합니다.
4. **커브** 또는 **수동**을 선택하고 권한 안내에서 **계속**을 누릅니다.
5. 승인이 필요하면 **시스템 설정 > 일반 > 로그인 항목 및 확장 프로그램**에서
   PenguinFan을 활성화합니다.

온도 모니터링에는 관리자 권한이 필요하지 않습니다. 실제 팬 제어를 요청할
때만 권한 서비스가 실행됩니다.

## 안전 설계

- 헬퍼는 상태, 하트비트, 제한 범위 RPM, 복귀, 종료 명령만 처리합니다.
- `/Applications` 아래 서명된 앱 번들 구조, 서명 식별자, Team ID, 콘솔 사용자와
  설치 경로 보안을 모두 확인합니다.
- 하트비트 손실, 연결 실패, 잠자기, 지속적인 센서 오류, 앱 종료 또는 System
  모드 선택 시 두 팬을 macOS 자동 제어로 복귀시킵니다.
- macOS thermal pressure가 위험 수준이면 최대 지원 팬 속도를 요청합니다.

직접 팬 제어는 냉각, 소음, 부품 온도와 하드웨어 수명에 영향을 줄 수
있습니다. 이 소프트웨어는 보증 없이 제공됩니다.

## 소스에서 빌드

필요 환경은 macOS 13 이상, Apple Silicon Mac, Swift 6 지원 Xcode입니다.

```bash
./script/build_and_run.sh --verify

./script/run_tests.sh
```

정식 권한 패키지를 만들려면 유효한 코드 서명 인증서가 필요합니다. 포크를
배포할 때는 번들 식별자와 Team ID를 자신의 값으로 변경해야 합니다.

## 제거

1. **시스템** 모드를 선택해 macOS가 팬을 제어하는지 확인합니다.
2. PenguinFan 설정에서 권한 서비스를 제거합니다.
3. PenguinFan을 종료합니다.
4. `/Applications/PenguinFan.app`을 삭제합니다.

## 참고한 오픈소스

- [agoodkind/macos-smc-fan](https://github.com/agoodkind/macos-smc-fan)
- [metaspartan/mactop](https://github.com/metaspartan/mactop)
- [angristan/MacThrottle](https://github.com/angristan/MacThrottle)
- [ryyansafar/MacMonitor](https://github.com/ryyansafar/MacMonitor)

서드파티 고지는 `LICENSES/`에 포함되어 있습니다.

## 라이선스

[MIT 라이선스](LICENSE). 개인 및 상업적 사용 모두 무료입니다.
