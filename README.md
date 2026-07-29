# Flick

**Flick** — 手机端 APP，发现局域网内的 [ClipLink Daemon](https://github.com/krustd/cliplinkd)，双向传输剪贴板内容和文件。

## 工作流

### 手机 → 电脑

1. 电脑启动 cliplinkd 守护进程
2. 手机打开 Flick APP → 自动扫描局域网设备
3. 点击设备 → 首次输入 PIN 码（之后自动记住）
4. 输入文本 → 点发送
5. 电脑端自动粘贴 → 手机显示"已发送"

### 电脑 → 手机（获取剪贴板）

1. 连接成功后，点击 📋「获取剪贴板」
2. 文本 ≤ 512KB 自动复制到手机剪贴板
3. 图片 / 文件 / 大文本弹出确认框，显示大小
4. 确认后下载：图片 → 相册，文件 → 下载目录

## 特性

- **剪贴板拉取**：获取电脑剪贴板（文本/图片/文件），大文件有进度条
- **多播发现 + 子网扫描**：224.0.0.167 多播 + Burst 首发；5 秒无结果自动 TCP 扫描 /24 子网

## 平台支持

| 平台 | 状态 | 备注 |
|------|------|------|
| Android | 正式支持 | 需 `INTERNET` 权限，Flutter 默认已配置 |
| iOS | 正式支持 | 首次使用需授权本地网络访问 |
| OpenHarmony | 兼容 | 通过 `flutter_harmony` 构建，`RawDatagramSocket` 可用；部分 ROM 可能限制 UDP 多播，降级为 TCP 子网扫描 |

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

## 项目结构

```
lib/
├── main.dart                      # 入口，Provider 注入 + 主题
├── models/
│   ├── discovered_device.dart     # 扫描发现的设备
│   ├── paired_device.dart         # 已配对设备（含 PIN）
│   └── send_result.dart           # 发送结果（sent / error）
├── providers/
│   └── app_state.dart             # ChangeNotifier 全局状态
├── services/
│   ├── discovery_service.dart     # 多播发现 + TCP 子网扫描
│   ├── socket_service.dart        # TCP 连接、认证、心跳、断线重连
│   ├── storage_service.dart       # SharedPreferences 配对存储
│   └── file_saver.dart            # 文件保存到下载目录（MediaStore）
├── screens/
│   ├── devices_screen.dart        # 设备列表 + 手动连接 + 配对管理
│   ├── pin_screen.dart            # PIN 码输入
│   └── send_screen.dart           # 文本发送 + 剪贴板拉取 + 进度条
└── test/
    └── widget_test.dart

## 依赖

| 包 | 用途 |
|----|------|
| `provider` | 状态管理 |
| `shared_preferences` | 本地配对信息持久化 |
| `uuid` | 消息去重 ID |
| `gal` | 图片保存到相册 |
| `path_provider` | 临时文件路径 |
| `dart:io` | TCP Socket / UDP RawDatagramSocket |

Flick 需要配合 [ClipLink Daemon (`cliplinkd`)](https://github.com/krustd/cliplinkd) 使用。请先在电脑上安装并启动守护进程。

## 许可

MIT License
