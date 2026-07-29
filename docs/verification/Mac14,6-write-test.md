# Mac14,6 Minimal Fan Write Verification

- Timestamp: 2026-07-29 10:21:29 KST
- Model: Mac14,6
- Scope: Fan 0 only
- Requested target: 1650 RPM
- Duration: 5 seconds
- Hardware range: 1350-5349 RPM
- Mode key: F0Md
- Firmware error: none

## Observations

| Time | Actual RPM | Target RPM |
| ---: | ---: | ---: |
| Before | 1353 | 1350 |
| 1 second | 1554 | 1650 |
| 2 seconds | 1642 | 1650 |
| 3 seconds | 1649 | 1650 |
| 4 seconds | 1647 | 1650 |
| 5 seconds | 1664 | 1650 |
| After restore | 1664 | 1350 |

## Result

- Fan response observed within the 400 RPM tolerance: PASS
- F0Md after restoration: 0
- System-auto restoration: PASS
- Overall minimal write verification: PASS

The post-restore actual RPM remained temporarily elevated because of fan
inertia, while the target returned to 1350 RPM and the mode key returned to
automatic control.
