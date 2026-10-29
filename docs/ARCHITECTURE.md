# StoneNavigationEmulation: архітектура

Документ описує, як влаштовано додаток за [SPEC.md](SPEC.md), і перелічує всі файли. Уточнення з коментарів до макета (підтвердження позиції за орієнтиром, бік дороги, коридор 50 м) теж враховані.

## Шари

```
┌──────────────────────────── iOS-додаток (SwiftUI) ────────────────────────────┐
│ Features/  екрани: карта, індикатор режиму, панель керування, запит про       │
│            підміну, орієнтири, пошук, налаштування, режим тестування          │
│ State/     AppModel, SettingsModel, SearchModel, SavedPlacesModel             │
│            (@Observable, через Environment)                                   │
│ Services/  реальні реалізації портів: CoreLocation, CoreMotion, AVSpeech,     │
│            UserDefaults, файл стану; MapKit/ окремо (RouteProvider, PlaceSearch)│
│ App/       збирання залежностей: живі порти або сценарій -scenario            │
└───────────────▲───────────────────────────────────────────────────────────────┘
                │ лише протоколи й чисті типи
┌───────────────┴──────────── Swift-пакет NavigationCore (без SwiftUI) ─────────┐
│ Geo/       Coordinate, Geo, RoutePolyline (рух і проєкція на polyline)        │
│ Model/     Route, Maneuver, LocationFix, Place, Landmark                      │
│ Settings/  NavigationSettings + межі, SettingsRepository (KeyValueStorage)    │
│ Engine/    NavigationEngine (машина станів), DeadReckoner, SpoofDetector,     │
│            TurnDetector                                                       │
│ Voice/     VoicePrompter, UkrainianFormat                                     │
│ Landmarks/ LandmarkSelector (коридор, орієнтир біля повороту, значки),        │
│            LandmarkPlanner (черга запитів), LandmarkLoadStatus                 │
│ Search/    BlockedCountries, SavedPlaces (дім, робота, збережені, останні)    │
│ Routing/   RouteCache, RequestThrottle (MKError.loadingThrottled)             │
│ GPX/       GPXTrack, ReplayPlanner (зникнення GPS і стрибок)                  │
│ Session/   NavigationSession (@Observable координатор портів і рушія)         │
│ Ports/     LocationSource, MotionSource, RouteProvider, PlaceSearch,          │
│            SpeechOutput, Clock, ModeLog, SessionStore                         │
│ Fakes/     фейки всіх портів для тестів і сценаріїв                           │
└───────────────────────────────────────────────────────────────────────────────┘
```

Пакет не імпортує SwiftUI, MapKit, CoreLocation і CoreMotion. Координати там свої (`Coordinate`), тому `swift test` іде на macOS без симулятора. Додаток перетворює CL- і MK-типи на типи пакета на межі `Services/`.

Google Maps із беклогу додається без переписування логіки: поруч із `Services/MapKit/` з'являється `Services/Google/` з `GoogleRouteProvider` і `GooglePlaceSearch`, а `AppContainer` вибирає реалізацію. Шар карти (`NavigationMapView`) отримує дані з `NavigationSession` (polyline, позиція, орієнтири) і не знає, звідки вони прийшли.

## Порти та їхні реалізації

| Протокол | Справжня реалізація | Фейк |
|---|---|---|
| `LocationSource` | `CoreLocationSource` (CLLocationManager, фон, «Завжди») | `FakeLocationSource` (ручні події), `ScriptedLocationSource` (розклад подій: сценарії, GPX) |
| `MotionSource` | `CoreMotionSource` (CMMotionActivityManager + CMMotionManager deviceMotion) | `FakeMotionSource` |
| `RouteProvider` | `MapKitRouteProvider` (MKDirections, кілька плечей для зупинок) | `FakeRouteProvider`, `FixtureRouteProvider` |
| `PlaceSearch` | `MapKitPlaceSearch` (MKLocalSearchCompleter, MKLocalSearch, MKLocalPointsOfInterestRequest), обгорнутий у `CountryFilteredPlaceSearch` | `FakePlaceSearch` (фікстура POI), теж через `CountryFilteredPlaceSearch` |
| `SpeechOutput` | `SystemSpeechOutput` (AVSpeechSynthesizer uk-UA, AVAudioSession .playback + .duckOthers) | `FakeSpeechOutput` |
| `Clock` | `SystemClock` | `FakeClock` |
| `ModeLog` | `OSModeLog` (os.Logger, subsystem = bundle ID, category `Mode`) | `RecordingModeLog` |
| `SessionStore` | `FileSessionStore` (JSON в Application Support) | `InMemorySessionStore` |
| `KeyValueStorage` | `UserDefaultsStorage` | `InMemoryKeyValueStorage` |

Адреси в Росії та Білорусі вимкнено (`BlockedCountries`, `CountryFilteredPlaceSearch` у NavigationCore). Фільтр обгортає будь-якого постачальника пошуку:
* підказки автодоповнення відкидаються, якщо в назві чи підзаголовку окремою частиною адреси стоїть назва країни («Москва, Росія», «Минск, Беларусь», «Russia» тощо українською, російською, білоруською, англійською). Слово в назві («вулиця Білоруська, Київ») не рахується;
* вибране місце (`resolve`) з кодом країни RU чи BY не можна взяти пунктом призначення чи стартом: пошук показує «Адреси в Росії та Білорусі вимкнено». Код береться з `MKMapItem.addressRepresentations.region`;
* орієнтири з кодом RU чи BY не потрапляють на маршрут.

Усі порти, крім `Clock`, `ModeLog` і `KeyValueStorage`, ізольовані на `@MainActor`: так простіше дотримати Swift 6 strict concurrency, бо MapKit, CoreLocation-делегати й SwiftUI однаково живуть на головному потоці. Синглтонів у логіці немає: `NavigationSession` отримує `NavigationPorts` через ініціалізатор, а екрани отримують сесію через `.environment(...)`.

## Машина станів режимів (`NavigationEngine`)

Рушій це чиста структура. Кожен метод приймає `now: Date`, тому тести керують часом через `FakeClock`.

```
                 помилка CL / застаріла точка (> staleAge) / точність > enterAccuracy /
                 немає точок staleAge / підміна (стрибок, неможлива швидкість, курс)
        ┌──────────────────────────────────────────────────────────────────────┐
        │                                                                      ▼
   ┌─────────┐   точність < returnAccuracy протягом returnDuration      ┌──────────────┐
   │   GPS   │◀────── і відстань до розрахункової ≤ spoofDistance ──────│ Розрахункова │
   └─────────┘                                                          │   позиція    │
        ▲            відстань > spoofDistance → запит «GPS показує      └──────────────┘
        │            інше місце. Перейти на GPS?» (за замовчуванням               │
        └──────────── «Лишити розрахункову»); «Перейти на GPS» ◀──────────────────┘
```

* `control`: `.automatic`, `.manualDeadReckoning` (ручний перемикач, автоматичного повернення немає) або `.manualGPS` («Все одно вести за GPS»: позиція йде за кожною точкою GPS без перевірок точності, віку й підміни, автоматичного переходу на розрахункову немає; без нових точок позиція стоїть).
* Перейти на GPS можна завжди. «Перейти на GPS» у панелі або в меню режиму (тап по індикатору вгорі, працює і зі згорнутою панеллю) перемикає одразу, якщо GPS придатний (`gpsAvailability == .usable`: точка свіжа і точніша за `enterAccuracy`). Якщо ні, меню показує стан GPS (неточний ±N м, остання точка N с тому, немає сигналу) і пропонує «Все одно вести за GPS» (`forceGPS`), а з ручної розрахункової ще й «Повернутися на GPS, коли стане точним». З ручного GPS є «Автоматичне перемикання» і «Розрахункова позиція». Перехід на GPS знімає паузу розрахункової точки.
* Під час входу в розрахунковий режим позиція екстраполюється від останньої доброї точки, щоб не відставати на `staleAge` секунд.
* Швидкість у розрахунковому режимі обирається за пріоритетом: ручна (+/−, діє до «Скинути»), потім середня швидкість маршруту (`distance / expectedTravelTime`), потім остання швидкість GPS, потім стандартна з Налаштувань. Пауза або стоянка за CoreMotion зупиняють точку.
* Коли датчики бачать стоянку, головна кнопка панелі стає «Рушити» (`ignoreStationary`): точка їде, хоч датчики й далі кажуть «стоянка» (телефон лежить на столі, а перевірити треба в русі, або датчик помилився). Це діє, доки датчики не побачать рух: наступна справжня стоянка знову зупинить точку. «Далі» після паузи теж знімає стоянку.
* Перехід плавний: відображувана позиція інтерполюється протягом `transitionDuration` (smoothstep). Сама оцінка змінюється відразу.
* Позиція завжди лежить на polyline. Якщо GPS далі за `offRouteThreshold`, з'являється «Перебудувати маршрут від моєї позиції».
* Коли гіроскоп фіксує поворот, напрямок збігається з найближчим поворотом маршруту попереду (у межах `turnSnapMaxDistance`), а точка ще не доїхала, рушій пропонує «Підтягнути до повороту».
* Ручні корекції: Вперед/Назад на `shiftStepMeters`, тап по лінії маршруту, підтвердження орієнтира («Я біля нього») і підтягування до повороту. Корекція в режимі GPS переводить у ручну розрахункову позицію.
* Старт із вибраної точки (`startAtChosenPoint`): маршрут прокладено не від моєї позиції, а від точки, яку вибрав водій. Якщо свіжий добрий GPS ближче за `spoofDistance` до старту, лишаємось на GPS. Інакше розрахункова позиція (причина «старт із вибраної точки») стоїть на початку маршруту на паузі, доки водій не натисне «Далі». Якщо GPS потім покаже інше місце, працює звичайний запит «Перейти на GPS?».

Детектор підміни (`SpoofDetector`) порівнює нову точку з попередньою доброю:
* `jump`: швидкість між точками неможлива і зсув більший за `spoofDistance`;
* `impossibleSpeed`: неможлива швидкість (після віднімання суми похибок обох точок) при меншому зсуві;
* `courseJump`: курс змінився більше ніж на `courseJumpDegrees` за ≤ `staleAge` при швидкості ≥ `courseMinSpeedKmh`, а на маршруті поруч (`turnProximity`) немає ні маневру, ні вигину.

## Орієнтири

* MapKit на один `MKLocalPointsOfInterestRequest` повертає обмежену кількість місць на весь регіон (у записаній фікстурі близько 20–25). Тому маршрут запитується невеликими шматками (`LandmarkArea`): **вікна по 500 м** уздовж polyline, **підʼїзди до поворотів** (250 м до маневру і 100 м після) і **половини вікон**, якщо вікно дало повну відповідь (≥ 20 місць). Регіон шматка дорівнює bounding box його polyline плюс коридор.
* `LandmarkPlanner.areas` впорядковує шматки за важливістю:
  1. вікно, де зараз позиція, і підʼїзд до найближчого повороту (навіть якщо поворот за 9 км);
  2. усе в межах 2 км попереду (`nearHorizon`): вікна й повороти, ближчі першими. Тож поруч орієнтири оновлюються весь час, услід за позицією;
  3. вікно позаду: якщо розрахункова точка забігла вперед, орієнтир позаду допоможе її виправити;
  4. ділянка наперед за SPEC: поточна ділянка `landmarkSegmentKm`, а наступна, коли пройдено половину поточної. Так орієнтири вже є, коли в тунелі зникнуть GPS і мережа.
* `NavigationSession` робить запити по одному. Після кожної відповіді наступний шматок вибирається заново (`LandmarkPlanner.next`): позиція могла зрушити. Для кожного шматка запам'ятовується, на які типи MapKit уже відповів. Запитуються лише ввімкнені типи. Тип, увімкнений пізніше, дозапитується лише він сам. Після помилки або `loadingThrottled` діє backoff `RequestThrottle`, готові шматки вдруге не запитуються.
* «Оновити орієнтири поруч» у списку (`refreshLandmarks`) заново запитує вікно позаду, 2 км попереду і найближчий поворот. Після збою мережі запит іде одразу. Після обмеження від самого MapKit оновлення чекає кінця паузи, бо інакше MapKit обмежить ще довше.
* Усі знайдені місця (`landmarkCandidates`, до 3000) лишаються в пам'яті і у збереженому стані. Після перебудови маршруту вони одразу стають орієнтирами нового маршруту, навіть без мережі.
* `LandmarkLoadStatus` (скільки попереду завантажено, скільки запитів, остання відповідь, помилка і час повтору) видно у списку орієнтирів, а кожен запит пишеться в журнал Mode: «Орієнтири: вікно 3 1500–2000 м, типів 7, знайдено 12». Пошук іде за категоріями MapKit, а не за текстом, тож мова телефону на нього не впливає.
* `LandmarkSelector` лишає місця, чия відстань до лінії маршруту ≤ `landmarkCorridor` (стандарт 50 м за коментарем у макеті; змінюється і в списку орієнтирів). Для кожного місця рахуються бік дороги (ліворуч чи праворуч за напрямком руху), відстань від дороги та позиція вздовж маршруту. Спершу місце перевіряється прямокутником навколо маршруту, а нові відповіді відбираються без повного перебору.
* MapKit відповідає помилкою `placemarkNotFound`, коли в шматку немає місць потрібних типів. Це не збій: шматок вважається завантаженим (порожнім), без червоної помилки, паузи й повторів.
* Орієнтир біля повороту (`LandmarkSelector.nearTurn`): найближчий до точки маневру в межах 120 м до неї і 40 м після. Банер маневру показує «біля: …». Голосові підказки за 300 і 100 м закінчуються «Орієнтир: АЗС WOG». На карті такі орієнтири в межах 2 км показуються першими і більшими (`LandmarkSelector.pins`), у списку позначені «біля повороту».
* На карті орієнтир показує `LandmarkMarker`: значок за типом із трикутником, вістря якого точно на місці, і підпис збоку з назвою та відстанню. Ширина підпису рахується наперед, тож точка прив'язки анотації (вістря) не залежить від довжини назви. Підпис стоїть з того боку, куди орієнтир відходить від дороги (`LandmarkSelector.labelSide`, з урахуванням курсу дороги біля орієнтира і повороту карти), тому лінію маршруту не закриває. Тап по значку відкриває картку.
* Назва довша за три слова скорочується з «…» (`LandmarkName.short`, тире й «&» словами не рахуються) на карті, у списку і в банері маневру. Тап по підпису на карті розгортає повну назву, ще тап скорочує. Повну назву видно в картці, її ж читає голос і VoiceOver.
* 17 типів (`PlaceCategory`): АЗС, зарядки, магазини, продукти, аптеки, кафе (з пекарнями), ресторани, пошта, банки (з банкоматами), готелі, лікарні, СТО, парковки, поліція, школи (з університетами), парки, пам'ятки. Стандартно ввімкнено 7 помітних з дороги: що більше типів, то менше місць кожного типу вміщає одна відповідь MapKit. Типи вмикаються у випадаючому меню (кнопка фільтрів у бічній колонці і рядок «Типи орієнтирів: N з 17» у списку): типи йдуть згори вниз, меню не закривається після кожного перемикача.
* Позиція береться з маршруту, а не з GPS, тож усе працює і в розрахунковому режимі.
* Картка орієнтира: назва, «через N км по маршруту», «праворуч · 35 м від дороги». Кнопки: **«Я біля нього: підтвердити позицію»** (головна), «Додати як зупинку», «Детальніше» (системна картка MapKit `mapItemDetailSheet` з графіком роботи), «Закрити».

## Збережені адреси

* `SavedPlaces` (NavigationCore): дім, робота, збережені й до 15 останніх пунктів призначення. Те саме місце (ближче за 30 м, навіть з назвою іншою мовою) не дублюється. Адреси в Росії та Білорусі не зберігаються. `SavedPlacesRepository` пише все одним JSON у `KeyValueStorage`.
* У пошуку без тексту видно «Мої адреси» (дім, робота, збережені, «Додати дім», «Додати роботу», «Зберегти адресу») і «Останні». З текстом адреси, що підходять (за назвою, адресою, а також «дім» і «робота»), стоять над підказками MapKit. Довгий тап по адресі чи підказці: «Зробити домом», «Зробити роботою», «Зберегти», «Прибрати». Останні поповнюються, коли маршрут до вибраного в пошуку місця побудовано.

## Маршрут, кеш, офлайн

* `MapKitRouteProvider` будує автомобільний маршрут через MKDirections. Зупинки йдуть окремими плечима, які зшиваються в один `Route`. `MKError.loadingThrottled` перетворюється на `RouteProviderError.throttled`.
* Точка відправлення: за замовчуванням моя позиція. Її можна змінити в пошуку (рядок «Звідки» перемикає пошук на вибір старту) або довгим тапом на карті («Звідси»; «Сюди» вибирає пункт призначення). Вибраний старт видно в рядку пошуку і маркером на карті, кнопка з іконкою геолокації повертає «Моя позиція». Після побудови маршруту старт скидається. `NavigationSession.buildRoute(to:from:)` передає точку в `MKDirections` і в `begin(route:…startPoint:)`.
* Довгий тап по карті під час навігації відкриває картку точки: наскільки вона від маршруту і де вздовж нього, і три дії. «Я тут» (`moveHere`) ставить позицію на маршрут навпроти точки, якщо до лінії не більше 100 м (`relocateTolerance`); далі кнопка недоступна. «Маршрут звідси» (`rebuildRoute(from:)`) після хибного повороту прокладає маршрут від точки до того самого пункту призначення з тими самими зупинками попереду; розрахункова точка, що їхала, їде далі новим маршрутом без паузи, а та, що стояла на паузі, чекає «Далі». «Сюди» прокладає маршрут від моєї позиції до точки як до нового пункту призначення.
* `RouteCache` зберігає відповіді за ключем (старт, фініш, зупинки, округлені до ~100 м) 12 годин. `RequestThrottle` після обмеження дає експоненційний backoff від 2 до 120 с. Маршрут перебудовується лише за явною дією: новий пункт, «Перебудувати», зупинка.
* `SessionSnapshot` (маршрут із кроками й polyline, пункт призначення, зупинки, позиція, ручна швидкість, орієнтири, кеш маршрутів) зберігається у файл під час старту навігації, кожні 15 с і при переході у фон. Після перезапуску навігація відновлюється без мережі.

## Голос

* `VoicePrompter` озвучує кожен маневр один раз на кожній дистанції (`voiceFarDistance`, `voiceNearDistance`) і на самому повороті (`voiceAtTurnDistance`), а в кінці каже «Ви прибули». Якщо позиція перестрибнула кілька порогів, звучить лише найближчий. Множина «метр / метри / метрів» українська. Якщо біля повороту є орієнтир, попередні підказки називають його: «Через 300 метрів поверніть праворуч… Орієнтир: АЗС WOG».
* `SystemSpeechOutput` використовує голос uk-UA і AVAudioSession `.playback`, режим `.voicePrompt`, `[.duckOthers, .interruptSpokenAudioAndMixWithOthers]`. Після фрази сесія деактивується з `.notifyOthersOnDeactivation`, щоб музика повернула гучність. Якщо голосу uk-UA немає, з'являється підказка з шляхом завантаження.

## Плавний рух і стеження

* Рушій рахує позицію раз на `updateInterval` (стандартно 1 с), а екран малює 30–60 разів на секунду (`FrameTicker` на CADisplayLink; у фоні зупиняється). Між оновленнями `PositionSmoother` веде точку далі зі швидкістю вздовж маршруту (`engine.alongSpeed`: у розрахунковому режимі швидкість рушія, 0 на паузі й стоянці; на GPS швидкість точки GPS) від моменту, коли рушій востаннє її зрушив (`session.alongUpdatedAt`). Розбіжність із новим розрахунком (точка GPS, «Вперед», зміна швидкості) зникає плавно (у e разів за 0,3 с). Без нових даних точка забігає наперед не більше ніж на 1,5 с; стрибок понад 300 м (новий маршрут) показується одразу. `HeadingSmoother` повертає курс на вершинах ламаної за ~0,4 с, коротшим шляхом через північ.
* Пауза, стоянка за датчиками і нова швидкість спершу довозять точку до миті натискання зі старою швидкістю (`changeMotion` → `engine.tick`). Раніше нова швидкість діяла на весь інтервал до наступного оновлення, і точка відскакувала назад після «Пауза» чи стрибала вперед після «Далі».
* Лінія маршруту ділиться на пройдене і попереду за позицією рушія, а не за плавною: лінії, що змінюються щокадру, MapKit не встигає намалювати. Різницю в кілька метрів ховає коло значка позиції.
* Стеження: камера щокадру йде за плавною точкою з висотою `followDistance` (стандартно 900 м, запам'ятовується). MapKit починає власний щипок чи перетягування, лише коли камера в мить дотику стоїть (перевірено в симуляторі), тому в стеженні MapKit лишається тільки масштабування (`interactionModes: [.zoom]`). Коли жест MapKit почався (`positionedByUser`), кадри не пишуть камеру; щойно вона 0,4 с стоїть, її висота стає висотою стеження. Щипок також обробляє `MagnifyGesture`, на випадок якщо жест MapKit під рухомою камерою не почнеться. Кнопки «+» і «−» унизу ліворуч (лише в стеженні) змінюють висоту вдвічі.
* Перетягування одним пальцем вимикає стеження і одразу зсуває карту під пальцем (масштаб посередині екрана рахується через `MapProxy`, вбік і вгору окремо, бо камера нахилена). Далі карта звичайна, з усіма жестами MapKit. «Центрувати» знову стежить, з тією висотою, що зараз на карті. Значок позиції не перехоплює дотики, тож щипок просто на ньому теж працює.

## Екран і фон

* `IdleTimerController` ставить `isIdleTimerDisabled = true`, поки йде навігація, увімкнено «Екран не гасне» і сцена активна. При завершенні навігації або переході у фон значення повертається в `false`.
* Необов'язкове затемнення: чорний шар після `dimAfter` секунд без дотиків. Знімається будь-яким дотиком (жест-спостерігач на вікні), яскравість не змінює, навігація триває. Біля налаштування є підказка про зарядку.
* Фон: `UIBackgroundModes = [location, audio]`, `allowsBackgroundLocationUpdates = true`, `pausesLocationUpdatesAutomatically = false`, дозвіл «Завжди». Цикл `tick()` іде на головному акторі й працює і з вимкненим екраном, бо застосунок тримають активним оновлення геолокації. Якщо iOS усе ж призупинила застосунок, наступний `tick` просуває точку на весь пропущений час.

## Налаштування

Усі числа зі SPEC зберігаються в `NavigationSettings`. Межі задані в `SettingKey.spec`, значення зберігаються через `SettingsRepository` у `KeyValueStorage` (UserDefaults у додатку). Логіка ядра отримує структуру й не читає UserDefaults.

| Ключ | Стандарт | Межі | Звідки |
|---|---|---|---|
| defaultSpeedKmh | 50 км/год | 10–130 | SPEC |
| speedStepKmh | 5 км/год | 1–20 | SPEC |
| shiftStepMeters | 50 м | 10–500 | SPEC |
| updateInterval | 1 с | 0,5–5 | SPEC |
| enterAccuracy | 100 м | 30–500 | SPEC |
| staleAge | 3 с | 1–30 | SPEC |
| returnAccuracy | 30 м | 5–100 | SPEC |
| returnDuration | 5 с | 1–30 | SPEC |
| spoofDistance | 500 м | 100–5000 | SPEC |
| impossibleSpeedKmh | 200 км/год | 120–400 | SPEC |
| offRouteThreshold | 50 м | 20–300 | SPEC |
| voiceFarDistance / voiceNearDistance | 300 / 100 м | 50–2000 | SPEC |
| landmarkSegmentKm | 10 км | 2–50 | SPEC |
| landmarkCorridor | **50 м** | **10–2000** | коментар у макеті (у SPEC 300 м, 100–2000) |
| dimAfter | 30 с | 10–300 | SPEC |
| courseJumpDegrees | 60° | 20–180 | додано: різка зміна курсу |
| courseMinSpeedKmh | 20 км/год | 5–80 | додано: на малій швидкості курс GPS шумить |
| turnProximity | 50 м | 10–300 | додано: «поруч немає повороту» |
| promptCooldown | 60 с | 10–600 | додано: пауза між запитами після «Лишити розрахункову» |
| transitionDuration | 2 с | 0–10 | додано: плавний перехід |
| voiceAtTurnDistance | 30 м | 5–100 | додано: «на самому повороті» |
| gyroTurnDegrees | 45° | 20–120 | додано: поворот за гіроскопом |
| turnSnapMaxDistance | 300 м | 50–2000 | додано: як далеко шукати поворот для підтягування |

Перемикачі: голос (увімк.), екран не гасне (увімк.), затемнення (вимк.), датчики руху (увімк.), фільтри 17 типів орієнтирів (увімкнені АЗС, магазини, продукти, аптеки, кафе, ресторани, пошта). Кнопка «Скинути до стандартних» скидає все.

Стан екрана, що не є налаштуванням, теж запам'ятовується: згорнуті нижня й верхня панелі, «північ зверху» (компас у бічній колонці), висота камери в стеженні, рука для нижньої панелі, збережені адреси.

Нижня панель стандартно під праву руку: «−», швидкість у колі, «+» і кнопки зсуву біля правого краю, «Пауза» і «GPS» ліворуч. Налаштування → «Нижня панель» → «Лівша» дзеркалить ряди (← лишається ліворуч від →). Підписи кнопок в один рядок дрібнішим шрифтом, а системний шрифт понад «Великий» панель не збільшує (`dynamicTypeSize(...large)`), тож вона лишається у два ряди.

Внутрішні евристики, що не впливають на поведінку, яку бачить користувач, лишаються константами з коментарями: вікно пошуку проєкції ±300/3000 м, вікно гіроскопа 8 с, ціна округлення ключа кешу.

## Тестованість

* `-scenario gps|lost|spoof|poi|settings|turn` запускає застосунок із `ScriptedLocationSource` і записаним маршрутом `test_route.json`, POI беруться з `test_pois.json`, мережевих запитів немає. `turn` починається за 375 м до повороту на Братиславську з орієнтиром біля нього. `-motion stationary` змушує фейкові датчики одразу повідомити стоянку. `-set ключ=значення` задає числове налаштування сценарію (наприклад, `-set shiftStepMeters=120`). У сценаріях `poi` і `lost` до записаних POI додано вигадане місце з довгою назвою за 260 м від старту, щоб перевірити скорочення назви. Також є `-loadRoute test`: справжні порти (CoreLocation тощо) плюс записаний маршрут, для живого прогону з `xcrun simctl location`.
* Фікстури (`test_route.json`, `test_pois.json`, `test_track.gpx`) лежать у `NavigationCore/Tests/NavigationCoreTests/Fixtures` і копіюються в бандл додатка як папка `Fixtures`. Маршрут і POI записує єдиний мережевий тест `MapKitIntegrationTests` (тег `.network`) із `RECORD_FIXTURES_DIR`. GPX синтезується з маршруту скриптом `scripts/make_gpx.py`.
* Переходи режимів пишуться в `os.Logger(subsystem: bundleID, category: "Mode")`, рух розрахункової точки логується раз на 5 с.
* Ключові елементи мають `accessibilityIdentifier`: `mode.indicator`, `mode.timer`, `speed.minus/plus/value/source/reset`, `shift.back/forward`, `pause.toggle`, `remaining.label`, `spoof.prompt/keep/switch`, `landmarks.list.button`, `landmark.row.N`, `landmark.card`, `landmark.confirm/addStop/details`, `landmarks.refresh/coverage/requests/found/error/ahead`, `landmarks.corridor.minus/plus`, `maneuver.landmark`, `pending.here/rebuild/go/origin/cancel/where`, `map.recenter`, `map.zoomIn/zoomOut`, `map.position` (значення: «стежу, висота камери N м» або «без стеження, …»), `landmark.pin.<id>`, `landmark.label.<id>`, `filter.*`, `list.filters`, `list.filter.*`, `arrival.caption`, `settings.hand`, `settings.*`, `route.rebuild`, `turn.snap`, `mode.switch`, `map.compass`, `saved.home/work/favorite.N/recent.N`, `saved.*.add`, `search.*`.
* Режим тестування в Налаштуваннях: програвання GPX з імітацією зникнення GPS і стрибка позиції (`ReplayPlanner` + `ScriptedLocationSource`).

## Файли

```
docs/  SPEC.md  ARCHITECTURE.md  TEST_REPORT.md  DEVICE_CHECKLIST.md  screenshots/
StoneNavigationEmulation/
  project.yml                                  XcodeGen (iOS 27, Swift 6, strict concurrency)
  scripts/make_gpx.py                          GPX-трек із записаного маршруту
  scripts/live_run.sh                          живий прогін на симуляторі (simctl privacy/location)
  scripts/screenshots.sh                       скріншоти сценаріїв у docs/screenshots
  NavigationCore/
    Package.swift
    Sources/NavigationCore/
      Geo/Coordinate.swift                     Coordinate, Geo (haversine, азимут), LocalProjection
      Geo/RoutePolyline.swift                  рух по polyline, проєкція, бік дороги, зріз, регіон
      Model/Route.swift                        Route, RouteStep, Maneuver, TurnDirection
      Model/Location.swift                     LocationFix, LocationEvent, MotionActivity, YawSample
      Model/Places.swift                       PlaceCategory, PlaceCandidate, Landmark, Place, GeoRegion
      Settings/NavigationSettings.swift        ключі, межі, стандарти, NavigationSettings
      Settings/SettingsRepository.swift        KeyValueStorage, InMemoryKeyValueStorage, репозиторій
      Engine/DeadReckoner.swift                швидкість і її джерело, пауза, стоянка
      Engine/SpoofDetector.swift               стрибок, неможлива швидкість, курс
      Engine/TurnDetector.swift                поворот за гіроскопом
      Engine/NavigationEngine.swift            машина станів режимів
      Engine/DisplayMotion.swift               плавна позиція і курс між оновленнями рушія
      Voice/UkrainianFormat.swift              відстані, час, множина
      Voice/VoicePrompter.swift                голосові тригери
      Landmarks/LandmarkSelector.swift         коридор, бік, відстань від дороги, орієнтир біля повороту, значки,
                                               бік підпису на екрані
      Landmarks/LandmarkName.swift             коротка назва: до трьох слів і «…»
      Landmarks/LandmarkPlanner.swift          черга запитів: вікна 500 м, повороти, 2 км попереду, ділянка наперед
      Landmarks/LandmarkLoadStatus.swift       стан завантаження для екрана «Орієнтири»
      Routing/RouteCache.swift                 кеш маршрутів
      Routing/RequestThrottle.swift            backoff після loadingThrottled
      Search/BlockedCountries.swift            без адрес у Росії та Білорусі: фільтр пошуку й орієнтирів
      Search/SavedPlaces.swift                 дім, робота, збережені, останні; репозиторій
      GPX/GPXTrack.swift                       парсер і запис GPX
      GPX/ReplayPlanner.swift                  розклад подій із зникненням і стрибком
      Session/SessionSnapshot.swift            збережений стан
      Session/NavigationSession.swift          @Observable координатор
      Ports/Ports.swift                        протоколи портів і помилки
      Ports/OSModeLog.swift                    os.Logger, категорія Mode
      Fakes/Fakes.swift                        фейки портів, FakeClock
      Fakes/ScriptedLocationSource.swift       програвання розкладу подій у реальному часі
    Tests/NavigationCoreTests/
      Fixtures/test_route.json  test_pois.json  test_track.gpx
      Support/TestSupport.swift                фікстури, синтетичний Г-подібний маршрут
      PolylineTests.swift  DeadReckoningTests.swift  ModeSwitchTests.swift
      ReturnToGPSTests.swift  SpoofDetectorTests.swift  SettingsTests.swift
      LandmarkTests.swift  VoicePrompterTests.swift  TurnDetectorTests.swift
      RoutingTests.swift  GPXTests.swift  FixtureTests.swift  SessionTests.swift
      ChosenStartTests.swift  ForceGPSTests.swift  BlockedCountriesTests.swift
      SavedPlacesTests.swift
  StoneNavigationEmulation/
    App/StoneNavigationApp.swift               @main, Environment
    App/AppContainer.swift                     збирання портів: живі або сценарій
    App/LaunchConfiguration.swift              -scenario, -loadRoute, -resetState, -motion, -set
    App/Scenarios.swift                        розклади подій сценаріїв, FixedMotionSource
    App/BundledFixtures.swift                  читання фікстур із бандла
    State/AppModel.swift                       стан екрана, цикл tick, затемнення, idle timer
    State/SettingsModel.swift                  редагування й збереження налаштувань
    State/SearchModel.swift                    пошук місця
    State/SavedPlacesModel.swift               збережені адреси
    Services/Location/CoreLocationSource.swift
    Services/Motion/CoreMotionSource.swift
    Services/Speech/SystemSpeechOutput.swift
    Services/Storage/UserDefaultsStorage.swift
    Services/Storage/FileSessionStore.swift
    Services/MapKit/MapKitRouteProvider.swift
    Services/MapKit/MapKitPlaceSearch.swift
    Services/MapKit/MapKitConversions.swift
    Services/MapKit/MapItemDetails.swift       MKMapItem для «Детальніше»
    Features/Root/RootView.swift               карта, панелі, рядок пошуку (капсула Liquid Glass)
    Features/Map/NavigationMapView.swift       Map, суцільна MapPolyline, власні Annotation, тап і довгий тап;
                                               відстань між значками орієнтирів залежить від масштабу карти
    Features/Map/MapMarkers.swift              маркер позиції, значок орієнтира з трикутником і підписом збоку
                                               (біля повороту більший)
    Features/HUD/ModeIndicatorView.swift       режим, таймер «без GPS»; тап відкриває вибір режиму
    Features/HUD/ModeOptions.swift             «Перейти на GPS», «Все одно вести за GPS», «Автоматичне перемикання»
    Features/HUD/ManeuverBanner.swift          банер маневру з орієнтиром біля повороту і CompactTopBar: верхня панель
                                               в один рядок (маневр + режим)
    Features/HUD/ControlPanel.swift            два ряди: Пауза/Далі/Рушити − швидкість у колі +; GPS, Назад/Вперед;
                                               під праву або ліву руку; згортається до рядка прибуття
    Features/HUD/SpoofPromptView.swift
    Features/HUD/Banners.swift                 перебудова, поворот, голос; бічні кнопки з компасом
    Features/Landmarks/LandmarkCardView.swift
    Features/Landmarks/LandmarkListView.swift  «Оновити поруч», стан завантаження, коридор, фільтри, список
    Features/Search/SearchView.swift           «Звідки» і «Куди», мої адреси й останні над підказками
    Features/Settings/SettingsView.swift
    Features/Settings/TestModeView.swift
    Features/Screen/DimmingOverlay.swift       затемнення і спостерігач дотиків
    Support/Style.swift                        кольори, великі кнопки
    Support/CoreLocation+Core.swift            CLLocationCoordinate2D ↔ Coordinate
    Support/FrameTicker.swift                  CADisplayLink: кадри для плавної точки і камери
    Assets.xcassets
  StoneNavigationEmulationUITests/
    ScenarioUITests.swift                      сценарії gps, lost, spoof, poi, settings
    RouteStartAndPanelUITests.swift            вибір точки відправлення, компактна панель і згортання, «Рушити»
    MapCompassUITests.swift                    компас: північ зверху або за напрямком руху
    MapFollowUITests.swift                     плавний рух точки; стеження на будь-якому масштабі
    MapPointUITests.swift                      довгий тап під час навігації: «Я тут», «Маршрут звідси», «Сюди»
    SavedPlacesUITests.swift                   дім, останні, збережені в пошуку
    LandmarkUITests.swift                      орієнтир біля повороту, «Оновити поруч», стан, коридор
    TopBarUITests.swift                        згортання верхньої панелі в один рядок
    GPSAndCountryUITests.swift                 перехід на GPS за бажанням, адреси в Росії та Білорусі
    ScreenshotTests.swift                      скріншоти в docs/screenshots
    UITestSupport.swift
  StoneNavigationEmulationIntegrationTests/
    MapKitIntegrationTests.swift               єдиний мережевий тест (тег .network), запис фікстур
```
