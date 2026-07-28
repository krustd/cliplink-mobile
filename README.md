# ClipLink Mobile

**ClipLink Mobile** — 手机端 APP，发现局域网内的 [ClipLink Daemon](https://github.com/krustd/cliplinkd) 并将文本发送到电脑剪贴板/自动粘贴。

## 工作流

```
1. 电脑启动 cliplinkd 守护进程
2. 手机打开 ClipLink APP → 自动扫描局域网设备
3. 点击设备 → 首次输入 PIN 码（之后自动记住）
4. 输入文本 → 点发送
5. 电脑端自动粘贴（如焦点为输入框）或仅写入剪贴板
6. 手机显示发送状态
```

## 特性

- **自动发现**：UDP 广播扫描局域网内的 ClipLink 守护进程
- **手动连接**：支持手动输入 IP:Port 连接
- **PIN 认证**：首次连接输入 PIN，之后自动记住（SharedPreferences 本地存储）
- **配对记忆**：已配对设备优先显示，点击即可连接
- **实时状态反馈**：已粘贴 / 已写入剪贴板 / 无聚焦输入框
- **断线重连**：指数退避自动重连（1s → 2s → 4s → ... → max 30s）

## 平台支持

| 平台 | 状态 | 备注 |
|------|------|------|
| Android | 正式支持 | 需 `INTERNET` 权限，Flutter 默认已配置 |
| iOS | 正式支持 | 首次使用需授权本地网络访问 |
| OpenHarmony | 兼容 | 通过 `flutter_harmony` 构建，`RawDatagramSocket` 可用；部分 ROM 可能限制 UDP 广播，降级为手动输入 IP |

## 构建

### 前置条件

- Flutter SDK >= 3.44
- Android SDK / Xcode（按目标平台）

### 命令

```bash
git clone https://github.com/krustd/cliplink-mobile.git
cd cliplink-mobile
flutter pub get

# Android
flutter build apk --release

# iOS
flutter build ios --release

# OpenHarmony（需安装 flutter_harmony 工具链）
# flutter build ohos --release
```

### 运行调试

```bash
flutter run
```

## 项目结构

```
lib/
├── main.dart                      # 入口，Provider 注入
├── models/
│   ├── discovered_device.dart     # 扫描发现的设备
│   ├── paired_device.dart         # 已配对设备（含 PIN）
│   └── send_result.dart           # 发送结果枚举
├── providers/
│   └── app_state.dart             # ChangeNotifier 全局状态
├── services/
│   ├── discovery_service.dart     # UDP 广播设备发现
│   ├── socket_service.dart        # TCP 连接、认证、心跳
│   └── storage_service.dart       # SharedPreferences 配对存储
├── screens/
│   ├── devices_screen.dart        # 设备列表 + 手动连接
│   ├── pin_screen.dart            # PIN 码输入
│   └── send_screen.dart           # 文本发送 + 状态显示
└── test/
    └── widget_test.dart
```

## 依赖

| 包 | 用途 |
|----|------|
| `provider` | 状态管理 |
| `shared_preferences` | 本地配对信息持久化 |
| `uuid` | 消息去重 ID |
| `dart:io` | TCP Socket / UDP RawDatagramSocket |

## 配对电脑端

ClipLink Mobile 需要配合 [ClipLink Daemon (`cliplinkd`)](https://github.com/krustd/cliplinkd) 使用。请先在电脑上安装并启动守护进程。

## 许可

MIT License
