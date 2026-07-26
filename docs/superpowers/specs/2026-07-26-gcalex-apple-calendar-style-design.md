# gcalex Apple 캘린더 스타일 UI 개편 설계 문서

- 날짜: 2026-07-26
- 상태: 승인 대기 (사용자 리뷰 전)
- 선행 문서: [2026-07-24-gcalex-design.md](2026-07-24-gcalex-design.md) (원 설계), [2026-07-26-gcalex-calendar-visual-redesign-design.md](2026-07-26-gcalex-calendar-visual-redesign-design.md) (주말 색상 + 리퀴드 글래스)

## 1. 목적

gcalex의 메인 캘린더 화면을 Apple 캘린더 앱의 실제 UI 패턴에 더 가깝게 맞춘다: 오늘 표시 색상, 타이포그래피/여백, 하단 "오늘" 버튼, 상단 내비게이션 구조(월/년이 실제 타이틀이 되고 스와이프로 달 이동).

## 2. 범위 및 전제

- Apple 캘린더 앱 전체(다중 캘린더, 주간/일간/연간 뷰 전환, 검색, 캘린더 목록, 리스트 뷰 등)를 복제하지 않는다. gcalex는 원래 설계부터 "단일 캘린더 + AI 챗으로 일정 관리"에 집중한 미니멀한 앱이며, 이번 개편은 이미 존재하는 월간 뷰 화면의 시각/내비게이션 디테일만 Apple에 더 가깝게 다듬는 것이다.
- **토요일=파란색은 유지한다.** 실제 Apple 캘린더 앱은 일요일만 빨간색으로 표시하고 토요일에 별도 색이 없다(파란 토요일은 한국 달력 앱들의 관례). 이번 "Apple처럼" 요청은 색상 자체가 아니라 타이포그래피/여백/오늘 표시/내비게이션 구조에 적용되는 것으로, 지난 라운드에서 사용자가 명시적으로 요청한 토요일 파란색 결정과 충돌하지 않는다.
- 이번 변경으로 `CalendarMonthView`의 공개 인터페이스가 실제로 바뀐다 — 지난 라운드("주말 색상 + 리퀴드 글래스")의 "인터페이스 불변" 제약은 그 라운드에 한정된 것이며, 이번 기능(하단 "오늘" 버튼이 현재 보고 있는 달의 상태를 알아야 함)은 인터페이스 변경을 요구한다.
- AI/캘린더 동기화 로직(`ChatEngine.swift`, `CalendarTools.swift`, `GoogleCalendarService.swift`, `EventStore.swift`, `NotificationScheduler.swift`, `BackgroundRefreshCoordinator.swift`)은 이번 변경 대상이 아니다.

## 3. 아키텍처

### 3.1 시각 스타일

`CalendarMonthView.swift`의 `dayCell(for:)` 내부 스타일을 조정한다:
- **오늘 표시**: 배경 원 색을 `Color.blue` → `Color.red`로 변경 (숫자는 계속 흰색 유지, 실제 Apple 캘린더와 동일).
- **날짜 숫자 폰트**: `.body`(17pt regular) → `.system(size: 20, weight: .medium)`.
- **요일 헤더 폰트**: `.caption` → `.caption` + `.fontWeight(.medium)`.
- **셀 최소 높이**: 36pt → 44pt.

토요일 파란색(`WeekdayColor.color(forWeekday:)`)은 변경하지 않는다.

### 3.2 `visibleMonth` 상태를 RootView로 끌어올리기

현재 `visibleMonth`는 `CalendarMonthView` 내부 `@State` 전용이라 `RootView`가 "지금 보고 있는 달이 이번 달인지"를 알 방법이 없고, "오늘로 점프"를 명령할 방법도 없다. `visibleMonth`를 `RootView`의 `@State`로 옮기고 `CalendarMonthView`에는 `@Binding`으로 전달한다.

**`CalendarMonthView`의 새 공개 인터페이스**:
```swift
init(calendar: Calendar, eventDates: Set<DateComponents>, visibleMonth: Binding<Date>, onSelect: @escaping (Date) -> Void)
```
(기존 `calendar:eventDates:onSelect:`에 `visibleMonth: Binding<Date>`가 추가됨.)

`CalendarMonthView`는 더 이상 자체 헤더(달 타이틀, 화살표 버튼, 유리 캡슐)를 그리지 않는다 — 순수하게 "주어진 `visibleMonth`에 대한 요일 헤더 + 날짜 그리드"만 렌더링하고, 좌우 스와이프 제스처로 `visibleMonth`를 앞뒤로 바꾼다. 스와이프 제스처는 `LazyVGrid`를 감싸는 컨테이너에 `.simultaneousGesture(DragGesture(minimumDistance: 30))`로 붙여서 날짜 셀의 탭 제스처와 충돌하지 않게 한다. 좌→우로 50pt 이상 드래그하면 이전 달, 우→좌면 다음 달로 이동한다.

### 3.3 RootView: 내비게이션 재구성

- `.navigationTitle("gcalex")` 제거. 대신 `visibleMonth`를 "yyyy년 M월" 포맷으로 표시하는 **월/년 자체가 내비게이션 타이틀**이 되도록 `.navigationTitle(monthTitle)` + `.navigationBarTitleDisplayMode(.large)`.
- 툴바(`ToolbarItem(placement: .topBarLeading)` / `.topBarTrailing`)에 이전/다음 달 chevron 버튼을 배치 — 스와이프의 보조 수단으로, 발견성을 위해 유지. 이 버튼들은 표준 툴바 항목이라 iOS 26에서 자동으로 리퀴드 글래스 처리된다(추가 코드 불필요, 지난 라운드에서 이미 확인됨). "설정" 링크는 계속 trailing 쪽에 유지.
- `.safeAreaInset(edge: .bottom)`으로 **"오늘" 버튼**을 추가한다. `Calendar.isDate(visibleMonth, equalTo: Date(), toGranularity: .month)`가 `false`일 때만(즉 이번 달이 아닐 때만) 나타나고, 탭하면 `visibleMonth = Date()`로 되돌린다. `.buttonStyle(.glassProminent)` 적용, 표시/숨김에 `.transition(.opacity)` + 애니메이션을 줘서 부드럽게 나타나고 사라지게 한다.

## 4. 영향받는 파일

- **수정**: `gcalex/gcalex/UI/CalendarMonthView.swift` — 인터페이스 변경(`visibleMonth: Binding<Date>` 추가), 내부 헤더 제거, 스와이프 제스처 추가, 오늘=빨강, 타이포/여백 조정
- **수정**: `gcalex/gcalex/App/RootView.swift` — `visibleMonth` 상태 소유, 월 타이틀/툴바 chevron/하단 "오늘" 버튼 추가, `CalendarMonthView` 호출부를 새 인터페이스로 갱신

`WeekdayColor.swift`, `MonthGrid.swift`, `ChatView.swift`, `DayDetailSheet.swift`, `SettingsView.swift`, AI/동기화 로직 파일은 이번 변경 대상이 아니다.

## 5. 에러 처리

순수 시각/내비게이션 변경이라 새로운 에러 케이스가 발생하지 않는다. 스와이프 제스처의 임계값(50pt) 미만 드래그는 무시되어 아무 동작도 하지 않는다.

## 6. 테스트 전략

- `MonthGrid`/`WeekdayColor`는 이번 변경 대상이 아니라 기존 테스트 그대로 유지된다.
- "현재 보고 있는 달이 이번 달인지" 판정은 Foundation의 `Calendar.isDate(_:equalTo:toGranularity:)`를 직접 사용하는 한 줄 로직이라 별도 커스텀 헬퍼로 감싸 테스트하지 않는다 — 이미 검증된 시스템 API를 그대로 쓰는 것이므로 감쌀 이유가 없다.
- `CalendarMonthView`/`RootView`의 스와이프 제스처, 툴바 버튼, "오늘" 버튼은 이 프로젝트의 기존 관례대로(SwiftUI 뷰 본체는 자동 테스트 없이 컴파일 확인 + 시뮬레이터 수동 확인) 검증한다.

## 7. 범위 제외 항목

- 다중 캘린더 목록, 주간/일간/연간 뷰 전환, 검색, 일정 상세 팝오버 등 Apple 캘린더의 다른 화면/기능 — gcalex의 원래 설계 범위 밖.
- 월 단위 연속 스크롤(Apple의 확대/축소 뷰가 쓰는 방식) — 스와이프 페이징으로 대체, 아키텍처 변경 폭이 커서 이번 범위 제외.
