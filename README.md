# Flick

**Flick** — 手机端 APP，发现局域网内的 [ClipLink Daemon](https://github.com/krustd/cliplinkd)，双向传输剪贴板内容，并向电脑发送文本、图片和文件。

## 工作流

### 手机 → 电脑

1. 电脑启动 cliplinkd 守护进程
2. 手机打开 Flick APP → 自动扫描局域网设备
3. 点击设备 → 首次输入 PIN 码（之后自动记住）
4. 输入文本、选择图片或选择文件
5. 确认发送；图片直接写入电脑剪贴板，文件缓存到电脑后作为文件引用写入剪贴板并自动粘贴

### 电脑 → 手机（获取剪贴板）

1. 连接成功后，点击 📋「获取剪贴板」
2. 文本 ≤ 512KB 自动复制到手机剪贴板
3. 图片 / 文件 / 大文本弹出确认框，显示大小
4. 确认后下载：图片 → 相册，文件 → 下载目录

## 特性

- **剪贴板拉取**：获取电脑剪贴板（文本/图片/文件），大文件有进度条
- **发送图片与文件**：图片按 PNG/JPEG 写入电脑剪贴板；普通文件分块上传，显示确认和真实进度
- **多播发现 + 子网扫描**：224.0.0.167 多播 + Burst 首发；5 秒无结果自动 TCP 扫描 /24 子网

## 平台支持

| 平台 | 状态 | 备注 |
|------|------|------|
| Android | 正式支持 | 系统图片 / 文件选择器；需 `INTERNET` 权限 |
| iOS | 正式支持 | 首次选择图片时请求相册访问权限；首次使用需授权本地网络访问 |
| OpenHarmony | 基础连接兼容 | 附件选择依赖尚未在 OpenHarmony 工具链验证；不可用时会显示选择失败，不影响文本与剪贴板拉取 |

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
│   ├── send_result.dart           # 文本发送状态
│   └── upload_state.dart          # 附件上传状态与进度
├── providers/
│   └── app_state.dart             # ChangeNotifier 全局状态
├── services/
│   ├── discovery_service.dart     # 多播发现 + TCP 连接与上传协议
│   ├── storage_service.dart       # SharedPreferences 配对存储
│   └── file_saver.dart            # 文件保存到下载目录（MediaStore）
├── screens/
│   ├── devices_screen.dart        # 设备列表 + 手动连接 + 配对管理
│   ├── pin_screen.dart            # PIN 码输入
│   └── send_screen.dart           # 文本、附件发送与剪贴板拉取
└── test/
    ├── upload_state_test.dart     # 上传状态单元测试
    └── widget_test.dart

## 依赖

| 包 | 用途 |
|----|------|
| `provider` | 状态管理 |
| `shared_preferences` | 本地配对信息持久化 |
| `uuid` | 消息去重 ID |
| `crypto` | 上传文件完整性摘要 |
| `flutter_plugin_android_lifecycle` | 与当前 Android 构建链兼容的文件选择器生命周期依赖 |
| `file_picker` | 系统文件选择器 |
| `image_picker` | 系统图库选择器 |
| `gal` | 图片保存到相册 |
| `path_provider` | 临时文件路径 |
| `dart:io` | TCP Socket / UDP RawDatagramSocket |

Flick 需要配合 [ClipLink Daemon (`cliplinkd`)](https://github.com/krustd/cliplinkd) 使用。请先在电脑上安装并启动守护进程。

## 许可

MIT License
