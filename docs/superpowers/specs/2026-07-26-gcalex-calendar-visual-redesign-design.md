# gcalex 캘린더 시각 개편 설계 문서

- 날짜: 2026-07-26
- 상태: 승인 대기 (사용자 리뷰 전)
- 선행 문서: [2026-07-24-gcalex-design.md](2026-07-24-gcalex-design.md) (원 설계), 구현 완료 후 추가 요청

## 1. 목적

기존 gcalex 앱(11개 태스크로 구현 완료, `google-calender-ai/app` 저장소에 푸시됨)에 두 가지 시각적 개선을 추가한다.

1. 주말(토/일) 날짜를 색으로 구분 — 일요일은 빨간색, 토요일은 파란색. 날짜 숫자와 요일 헤더 글자 모두에 적용.
2. 앱 전체의 시각적 톤을 Apple의 iOS 26 Liquid Glass 디자인 언어로 일관되게 맞춘다.

## 2. 범위 및 전제

- **주말 범위**: 토요일/일요일만 대상으로 한다. 실제 대한민국 공휴일(설/추석 등)은 포함하지 않는다 — 별도의 공휴일 데이터 소스(하드코딩된 날짜 목록 또는 구글의 공유 공휴일 캘린더 연동)가 필요한 별개 기능이라 이번 범위에서 제외.
- **색 적용 위치**: 날짜 숫자와 요일 헤더("일 월 화 수 목 금 토") 글자 모두.
- **리퀴드 글래스 적용 범위**: 앱 전체에 일관되게 적용하되, 캘린더 그리드의 날짜 셀 배경 자체는 제외 (아래 4절 참고).
- AI 로직(ChatEngine, Foundation Models Tools, GoogleCalendarService, EventStore, NotificationScheduler, BackgroundRefreshCoordinator)은 이번 변경의 대상이 아니다. 순수 시각적 변경.

## 3. 기술적 배경 — UICalendarView의 제약

기존 `CalendarMonthView.swift`는 `UICalendarView`(UIKit 네이티브 컴포넌트)를 `UIViewRepresentable`로 감싸는 방식이었다. iOS 26 SDK의 실제 헤더(`UICalendarView.h`)를 직접 확인한 결과, `UICalendarViewDelegate`가 제공하는 공개 API는 다음 두 개뿐이다.

- `calendarView(_:decorationForDateComponents:)` — 날짜별 작은 데코레이션(점/이미지/커스텀뷰)을 반환. 날짜 숫자 자체의 글자색이나 요일 헤더 색을 바꾸는 기능은 없음.
- `calendarView(_:didChangeVisibleDateComponentsFrom:)` — 월 이동 콜백.

즉 **날짜 숫자나 요일 헤더의 텍스트 색을 바꾸는 공개 API가 UICalendarView에는 존재하지 않는다.** 이는 원 설계 문서(2026-07-24)에서 이미 "UICalendarView 데코레이션 커스터마이징이 약간 제한적"이라고 트레이드오프로 명시했던 부분이 이번 요구사항에서 실제로 막힌 것이다.

## 4. 아키텍처

### 4.1 캘린더 그리드: SwiftUI 자체 구현으로 교체

`CalendarMonthView.swift`를 `UIViewRepresentable` 래퍼에서 순수 SwiftUI `LazyVGrid` 기반 컴포넌트로 전면 재작성한다.

**공개 인터페이스는 유지**: `CalendarMonthView(eventDates: Set<DateComponents>, onSelect: @escaping (Date) -> Void)` — 기존과 동일하게 유지해서 `RootView` 쪽 연동 코드 변경을 최소화한다.

**내부 구성**:
- `@State private var visibleMonth: Date` — 현재 표시 중인 월을 자체 관리 (기존에는 `UICalendarView`가 관리했음).
- 요일 헤더 행: "일 월 화 수 목 금 토" 텍스트, 일요일은 빨간색(`.red`), 토요일은 파란색(`.blue`), 나머지는 기본 라벨 색(`.primary`).
- 7열 `LazyVGrid`로 날짜 셀 배치. 각 셀은:
  - 날짜 숫자 텍스트 — 요일에 따라 위와 동일한 색 규칙 적용.
  - 오늘 날짜는 배경에 원형 강조(`.blue`로 채운 `Circle`, 기존 이벤트 점과 동일 계열 색) — 기존 `UICalendarView`가 기본 제공하던 "오늘" 표시를 자체 구현으로 대체. 오늘이 토요일/일요일이라도 이 원 위의 숫자는 요일 색 대신 흰색으로 표시해 가독성을 유지한다(원 배경과 요일색이 충돌하지 않도록).
  - `eventDates`에 해당 날짜가 포함되어 있으면 숫자 아래 작은 점 표시 (기존 `.systemBlue` 데코레이션 점과 동일한 색으로 그대로 재현).
  - 탭하면 `onSelect(date)` 호출 — 동작은 기존과 동일.
- 이전/다음 달 이동은 컴포넌트 내부의 버튼으로 처리 (`visibleMonth`를 월 단위로 증감).

### 4.2 리퀴드 글래스 적용

iOS 26 SDK(`SwiftUICore.swiftinterface`)에서 실제로 확인한 API를 사용한다:
- `View.glassEffect(_ glass: Glass = .regular, in shape: some Shape) -> some View`
- `GlassEffectContainer<Content>` — 여러 유리 요소를 그룹화할 때
- `Glass` 구조체: `.regular`, `.clear`, `.tint(_:)`, `.interactive(_:)`
- `GlassButtonStyle`(`.glass`), `GlassProminentButtonStyle`(`.glassProminent`)

**적용 대상**:
- 메인 화면 상단 타이틀/월 네비게이션 바 영역
- `DayDetailSheet`의 시트 컨테이너 배경
- `ChatView`의 어시스턴트 말풍선, 하단 입력창 바
- 확인/취소 카드(`ConfirmationCenter` 렌더링 부분)
- `SettingsView`의 섹션/버튼
- 전송 버튼, 확인 버튼 → `.glassProminent` 버튼 스타일

**의도적으로 제외 — 캘린더 그리드의 날짜 셀 배경**: 유리 재질은 반투명이라 작고 빽빽한 텍스트(날짜 숫자) 위에 깔면 가독성이 떨어지고, 방금 추가한 주말 빨강/파랑 색상도 흐려진다. Apple 캘린더 앱 자신도 월간 그리드 안에는 유리 재질을 쓰지 않고 내비게이션/컨트롤 레이어에만 사용한다 — 이 관례를 따른다. 날짜 셀은 일반(불투명) 배경을 유지하고, 유리는 그 위/주변의 내비게이션·시트·카드·버튼에만 적용한다.

## 5. 영향받는 파일

- **재작성**: `gcalex/gcalex/UI/CalendarMonthView.swift` (UIViewRepresentable → 순수 SwiftUI)
- **수정**: `gcalex/gcalex/UI/ChatView.swift` (말풍선/입력창/확인카드에 glass 적용)
- **수정**: `gcalex/gcalex/UI/DayDetailSheet.swift` (시트 컨테이너에 glass 적용)
- **수정**: `gcalex/gcalex/UI/SettingsView.swift` (glass 적용)
- **수정**: `gcalex/gcalex/App/RootView.swift` (상단 타이틀/네비게이션 바에 glass 적용; `CalendarMonthView` 호출부는 인터페이스가 동일하므로 최소 변경)

AI/캘린더 로직 파일(`ChatEngine.swift`, `CalendarTools.swift`, `GoogleCalendarService.swift`, `EventStore.swift`, `NotificationScheduler.swift`, `BackgroundRefreshCoordinator.swift`)은 이번 변경 대상이 아니다.

## 6. 에러 처리

이번 변경은 순수 시각적 개편이라 새로운 에러 케이스가 발생하지 않는다. 기존 확인 카드의 승인/취소 로직, 알림 권한 요청 흐름 등은 그대로 유지되며 시각적 스타일만 바뀐다.

## 7. 테스트 전략

- **요일→색상 매핑 로직**을 순수 함수로 분리(예: `enum WeekdayColor { static func color(for weekday: Int) -> Color }`)해 유닛 테스트로 검증 — 일요일(1)=빨강, 토요일(7)=파랑, 평일=`.primary`.
- **월간 그리드의 날짜 배열 생성 로직**(해당 월의 실제 날짜 + 앞뒤 공백 채우기)을 순수 함수로 분리해 유닛 테스트로 검증 — 예: 2026년 7월은 수요일(7/1)부터 시작하므로 앞에 3칸의 빈 셀이 와야 함.
- `CalendarMonthView`/`ChatView`/`DayDetailSheet`/`SettingsView`/`RootView`의 SwiftUI 뷰 본체 자체는 기존 프로젝트 컨벤션(이 파일들은 원래도 자동 테스트 없이 컴파일 확인 + 수동 테스트로 검증됨)을 따라 컴파일 확인과 시뮬레이터 수동 확인으로 검증한다.

## 8. 범위 제외 항목

- 실제 대한민국 공휴일 표시 (설/추석 등) — 별도 데이터 소스 필요, 향후 별도 기능으로 다룸.
- 캘린더 그리드 날짜 셀 배경에 유리 재질 적용 — 가독성 저하로 의도적 제외.
- AI 챗/일정 생성·수정·삭제 로직 변경 — 이번 범위 아님.
