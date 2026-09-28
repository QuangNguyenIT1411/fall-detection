# Fall Detection Dashboard

Flutter Web Dashboard cho đồ án **Hệ thống phát hiện té ngã cho người cao tuổi sử dụng ESP32-C3 + MPU6500**.

> Trạng thái: **Phase 8 – đã chuẩn bị Flutter Web cho Vercel; chưa deploy**.

## Kiến trúc

```text
MQTT Broker ── WSS ──> Flutter Web       (telemetry/state/status realtime)
Supabase PostgreSQL ──> Flutter Web       (thiết bị và lịch sử sự kiện)
MockTelemetryService ─> Flutter Web       (debug khi thiếu cấu hình MQTT)
```

- MQTT không ghi telemetry định kỳ vào PostgreSQL.
- Supabase browser client chỉ có quyền `SELECT` theo RLS.
- `TelemetryProvider` nhận cùng một loại `RealtimeUpdate` từ mock hoặc MQTT, giữ tối đa 60 điểm.
- Broker connection và trạng thái online của thiết bị là hai trạng thái độc lập.

## Phần cứng

- ESP32-C3 LuatOS CORE
- MPU6500: I2C `0x68`, SDA GPIO6, SCL GPIO7
- Buzzer GPIO4, LED đỏ GPIO5, nút CANCEL GPIO3
- Firmware V3.1 chưa bị thay đổi trong Phase 3

## Cấu trúc chính

```text
lib/
├── main.dart
├── core/
│   ├── config/mqtt_config.dart
│   ├── config/supabase_config.dart
│   └── theme/app_theme.dart
├── models/
│   ├── telemetry.dart
│   ├── realtime_update.dart
│   ├── device.dart
│   └── fall_event.dart
├── providers/
│   ├── telemetry_provider.dart
│   └── fall_event_provider.dart
├── services/
│   ├── telemetry_data_source.dart
│   ├── mock_telemetry_service.dart
│   ├── mqtt_service.dart
│   ├── supabase_service.dart
│   └── fall_event_repository.dart
└── screens/ và widgets/
```

## MQTT Topics

`MQTT_DEVICE_CODE=device01` tạo ra:

```text
fall/device01/telemetry
fall/device01/state
fall/device01/status
```

### Telemetry payload

```json
{
  "device_id": "device01",
  "acc": 1.03,
  "gyro": 11.5,
  "pose": 8.2,
  "state": "NORMAL",
  "timestamp": 1720000000000
}
```

Các state hợp lệ: `NORMAL`, `FALLING`, `IMPACT`, `POSTURE`, `FALL_DETECTED`.

### State payload

```json
{
  "device_id": "device01",
  "state": "FALL_DETECTED",
  "timestamp": 1720000000000
}
```

State topic được xử lý ngay, không chờ telemetry tiếp theo.

### Status payload

```json
{
  "device_id": "device01",
  "online": true,
  "timestamp": 1720000000000
}
```

Khi broker mất kết nối, dashboard giữ device ở trạng thái gần nhất thay vì tự suy luận `OFFLINE`.

## Cấu hình HiveMQ Cloud Serverless

HiveMQ Cloud Serverless có free tier, MQTT over TLS, WebSocket và basic authorization.

1. Tạo tài khoản HiveMQ Cloud và tạo cluster **Serverless FREE**.
2. Mở cluster, vào **Access Management**.
3. Tạo credential cho dashboard với quyền **Subscribe** trên `fall/device01/#`. Không cấp Publish.
4. Tạo credential khác cho MQTTX/test publisher với quyền **Publish** trên `fall/device01/#`.
5. Trong thông tin kết nối của cluster, lấy hostname và **TLS WebSocket URL**.
6. HiveMQ Cloud WebSocket TLS dùng port `8884`. Lấy path từ TLS WebSocket URL; thường là `/mqtt`, nhưng nên dùng đúng URL cluster hiển thị.
7. Có thể dùng tab **Web Client** của cluster để kiểm tra connect và subscribe.

Trên Serverless, credential được gắn trực tiếp với permission. Các plan cao hơn hỗ trợ role/permission chi tiết hơn. Không dùng chung credential dashboard với ESP32 hoặc publisher.

## Dart defines MQTT

| Biến | Ví dụ | Ý nghĩa |
|---|---|---|
| `MQTT_HOST` | `abc.s1.eu.hivemq.cloud` | Host, không kèm scheme/path |
| `MQTT_PORT` | `8884` | WebSocket TLS port |
| `MQTT_USERNAME` | `dashboard-reader` | Credential chỉ Subscribe |
| `MQTT_PASSWORD` | `...` | Password broker |
| `MQTT_USE_TLS` | `true` | Tạo URL `wss://` |
| `MQTT_WEBSOCKET_PATH` | `/mqtt` | Path lấy từ WebSocket URL |
| `MQTT_DEVICE_CODE` | `device01` | Dùng để build topic |

Credential trong browser có thể bị người dùng xem. ACL broker mới là lớp bảo vệ chính; dashboard account phải read-only.

## Chạy ứng dụng

### Mock mode

Không truyền MQTT defines:

```powershell
flutter run -d chrome
```

Dashboard ghi rõ nguồn `MOCK`; nút **Mô phỏng té ngã** hoạt động như Phase 1.

### MQTT mode

PowerShell một dòng:

```powershell
flutter run -d chrome --dart-define=MQTT_HOST=YOUR_HOST --dart-define=MQTT_PORT=8884 --dart-define=MQTT_USERNAME=YOUR_READ_ONLY_USERNAME --dart-define=MQTT_PASSWORD=YOUR_PASSWORD --dart-define=MQTT_USE_TLS=true --dart-define=MQTT_WEBSOCKET_PATH=/mqtt --dart-define=MQTT_DEVICE_CODE=device01
```

Có thể nối thêm Supabase:

```powershell
flutter run -d chrome --dart-define=MQTT_HOST=YOUR_HOST --dart-define=MQTT_PORT=8884 --dart-define=MQTT_USERNAME=YOUR_READ_ONLY_USERNAME --dart-define=MQTT_PASSWORD=YOUR_PASSWORD --dart-define=MQTT_USE_TLS=true --dart-define=MQTT_WEBSOCKET_PATH=/mqtt --dart-define=MQTT_DEVICE_CODE=device01 --dart-define=SUPABASE_URL=YOUR_PROJECT_URL --dart-define=SUPABASE_ANON_KEY=YOUR_PUBLISHABLE_KEY
```

Khi MQTT config đầy đủ, source tự chuyển sang `MQTT`; nút mô phỏng bị disable và không publish dữ liệu giả.

## Test MQTT khi chưa có ESP32

Dùng HiveMQ Web Client hoặc MQTTX với **publisher credential riêng**:

1. Chọn protocol WebSocket Secure/WSS.
2. Nhập host, port `8884`, path lấy từ TLS WebSocket URL và publisher username/password.
3. Publish QoS 0 vào `fall/device01/status` với payload status ở trên.
4. Publish payload telemetry vào `fall/device01/telemetry`.
5. Publish payload state `FALL_DETECTED` vào `fall/device01/state`.

Kết quả mong đợi:

- Broker chuyển thành `CONNECTED`.
- Device chuyển từ `UNKNOWN` thành `ONLINE` sau status message.
- ACC/GYRO/POSE và biểu đồ cập nhật sau telemetry.
- State đổi ngay sang `FALL_DETECTED` và banner cảnh báo xuất hiện.
- Banner ghi số đo là giá trị **hiện tại**, không giả làm peak value, và báo đang chờ sự kiện chính thức.
- Payload sai hoặc device ID không khớp bị bỏ qua, ứng dụng không crash.

## Reconnect

Khi mất broker, `MqttService` thử lại theo backoff `2s → 5s → 10s`, sau đó giữ khoảng 10 giây giữa các lần thử. Khi kết nối lại, service subscribe lại cả ba topic và giữ nguyên dữ liệu chart đang có.

## Supabase Setup

1. Tạo Supabase project.
2. Chạy `supabase/schema.sql` trong SQL Editor.
3. Chạy `supabase/seed.sql`.
4. Lấy Project URL và publishable key từ **Connect** hoặc **Settings → API Keys**.
5. Truyền bằng `SUPABASE_URL` và `SUPABASE_ANON_KEY`.

Supabase tiếp tục read-only trong Phase 3. Không có thay đổi schema hoặc quyền ghi.

## Giới hạn hàng đợi cloud trên ESP32

Sự kiện té ngã đang chờ gửi và trạng thái `cancel_pending` chỉ được giữ trong
RAM. Nếu ESP32 mất điện hoặc reset trước khi `create-fall-event` hoàn tất, sự
kiện pending có thể bị mất. Phase 5.5 không triển khai persistent queue/NVS.
Firmware hiện quản lý một vòng đời sự kiện té ngã chưa hoàn tất tại một thời
điểm; HTTPS chạy trong worker riêng và không chặn sensor loop.

## Kiểm tra và build

```powershell
flutter pub get
flutter analyze
flutter test
flutter build web --release
```

Build MQTT + Supabase:

```powershell
flutter build web --release --dart-define=MQTT_HOST=YOUR_HOST --dart-define=MQTT_PORT=8884 --dart-define=MQTT_USERNAME=YOUR_READ_ONLY_USERNAME --dart-define=MQTT_PASSWORD=YOUR_PASSWORD --dart-define=MQTT_USE_TLS=true --dart-define=MQTT_WEBSOCKET_PATH=/mqtt --dart-define=MQTT_DEVICE_CODE=device01 --dart-define=SUPABASE_URL=YOUR_PROJECT_URL --dart-define=SUPABASE_ANON_KEY=YOUR_PUBLISHABLE_KEY
```

Output nằm trong `build/web/`.

## Lộ trình

1. Flutter Web + mock data — hoàn thành
2. Supabase read-only — hoàn thành
3. MQTT WebSocket realtime — hoàn thành
4. ESP32 publish MQTT, không block sensor loop
5. ESP32 gửi sự kiện qua Edge Function
6. Confirm và Telegram backend — hoàn thành
7. Chuẩn bị Vercel Web — hoàn thành cấu hình, chưa deploy

## Phase 8: chuẩn bị triển khai Vercel

Vercel Project phải đặt **Root Directory** là `fall_detection_dashboard`.
[`vercel.json`](vercel.json) nằm ngay tại Flutter project root, không phải tại
repository root. Chọn Framework Preset `Other`; build command và output directory
đã được khai báo trong `vercel.json`:

```text
Build Command: bash scripts/build_vercel.sh
Output Directory: build/web
```

Script tải Flutter Linux **3.47.4** từ archive chính thức, kiểm tra SHA-256,
chạy `flutter pub get` rồi `flutter build web --release` với các `--dart-define`.
Không cần Flutter cài sẵn trên Vercel. Build đầu tiên có thể chậm vì phải tải SDK;
không giả định cache SDK của Vercel được giữ qua các lần build.

Trong **Project Settings → Environment Variables**, thêm các biến sau cho
Production (và Preview nếu cần test preview):

| Biến | Giá trị cần cấu hình |
|---|---|
| `MQTT_HOST` | Host HiveMQ, không có `wss://`, port hoặc path |
| `MQTT_PORT` | `8884` |
| `MQTT_USERNAME` | Tài khoản dashboard chỉ Subscribe `fall/device01/#` |
| `MQTT_PASSWORD` | Mật khẩu của tài khoản dashboard read-only |
| `MQTT_USE_TLS` | `true` |
| `MQTT_WEBSOCKET_PATH` | `/mqtt` |
| `MQTT_DEVICE_CODE` | `device01` |
| `SUPABASE_URL` | `https://nuwcsqdedelgfkjpmrsj.supabase.co` |
| `SUPABASE_ANON_KEY` | Supabase publishable key hoặc anon-role JWT |

Các giá trị `--dart-define` được biên dịch vào bundle trình duyệt. Vì vậy,
**MQTT_PASSWORD không bí mật với người xem trang**: tài khoản HiveMQ phải
được giới hạn Subscribe-only đúng topic. Tuyệt đối không đặt Supabase
service-role/secret key, Telegram token, device API key hoặc credential MQTT
của ESP32 vào Vercel project này. Sau khi thay đổi Environment Variables,
cần build/deploy mới để các giá trị mới có mặt trong Flutter bundle.

`/`, `/realtime`, `/history` và `/events/<UUID>` là Flutter path routes.
`vercel.json` chỉ rewrite các route ứng dụng này về `/index.html`, để asset
Flutter vẫn được phục vụ theo đường dẫn thật. Chi tiết event deep link sẽ
đọc UUID từ Supabase; route local `LOCAL-...` chỉ hữu ích trong phiên hiện tại.

Nếu thiếu biến production, script dừng trước khi build và nêu tên biến thiếu.
Nếu bundle production vẫn nhận cấu hình không hợp lệ, ứng dụng hiện màn báo lỗi
cấu hình thay vì âm thầm chuyển sang dữ liệu MOCK. Chạy local không có
`PRODUCTION_BUILD=true` vẫn giữ chế độ MOCK cho phát triển.

Chưa chạy deploy trong Phase 8. Sau khi đưa project lên Git, import repository
vào Vercel, đặt Root Directory như trên, thêm Environment Variables, kiểm tra
Preview rồi mới deploy Production. Sau deploy, thử tải trực tiếp `/history`
và `/events/<UUID>`, kiểm tra MQTT CONNECTED, thiết bị ONLINE và lịch sử.
