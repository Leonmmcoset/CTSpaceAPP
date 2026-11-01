# 验证记录

日期：2026-11-01。环境：Linux x64、Flutter 3.47.8 stable、Dart 3.13.7、JDK 21、Android SDK 36。

## 已完成

- Dart 格式检查通过，Flutter 静态分析无问题。
- 18 项自动化测试通过，生成了 `coverage/lcov.info`。覆盖 PoW、六位验证码输入/粘贴与提交参数保留、分页、URL 解析、令牌发送边界、会话过期、写请求不重试、消息去重/撤回/重连补页、Markdown 转换、安全问题登录、草稿队列及账号隔离、退出编辑器即时保存。
- 界面测试覆盖 390 × 844 手机导航、1360 × 900 桌面讨论双栏、360 × 800 与 1.4 倍字号、系统减少动画；新增的素材、小游戏、客服和装扮入口包含在导航测试中。
- Linux Release 已成功构建，并在 Xvfb 中实际启动，访问生产站点公开 GET 接口，检查了社区、讨论详情、发现、广场和设置。检查时使用游客状态及 `READ_ONLY_SMOKE=true`，未主动发帖、私信、下单或支付。
- [截图](screenshots/) 来自实际 Linux Flutter 窗口；手机截图为窗口调整到 390 × 844 的响应式界面，不能等同于 iOS/Android 实机截图。仅保留了已完成加载的截图。
- Android Debug 与三种 ABI 的 Release APK 已成功构建：armeabi-v7a、arm64-v8a、x86_64。Release 目前使用开发签名；arm64 APK 已通过 `apksigner verify`，并通过 `aapt dump badging` 核实应用 ID 为 `xyz.ctspace.forum`、名称为「创客次元」、最低 API 26。
- Apple 的 Info.plist/entitlements 可解析，两个 Podfile 通过 Ruby 语法检查。
- 手动打包工作流的 YAML、仅 workflow_dispatch 触发、五个目标、iOS 无签名构建与 Payload 结构、每个产物 retention-days=3 已进行本地结构校验。自动流程仅保留检查任务。

## 平台结论

| 平台 | 本次验证 | 仍需完成 |
| --- | --- | --- |
| Linux x64 | Release 构建、实际运行、公开内容和响应式界面检查 | 多种发行版、真实密钥环登录与文件操作验收 |
| Android | Debug / 三 ABI Release APK 构建、arm64 包元数据和签名验证 | 真实设备的登录、文件选择、支付和生命周期验收；正式发行签名 |
| iOS | 工程、最低版本、Keychain、图标和 CI 未签名 IPA 打包配置 | macOS 宿主构建、签名后真机测试 |
| macOS | 工程、网络/文件权限、Keychain、图标和 CI 配置 | macOS 宿主构建及运行 |
| Windows | 工程、AppUserModelID、图标、链接库和 CI 配置 | Windows 宿主构建及运行 |

当前环境不能构建 Apple 和 Windows 原生程序。GitHub 工作流文件已提交，但没有将本地检查写成远端 Actions 成功运行记录。

本机构建产物已整理到 Git 忽略的 `dist/`：三个架构的 Android APK、完整 Linux 运行目录的 `ctspace-linux-x64.tar.gz` 及 `SHA256SUMS`。安装包不提交到源码仓库。

## 联调边界

自动化测试使用模拟 API 传输，不调用生产写接口。没有测试账号，因此真实发帖、注册激活、私信群聊、积分红包、商城支付、密钥创建与用户专属数据尚待在测试环境联调。当前公开直播接口返回 session=null，OrigMark 独立官网返回 521；登记契约和实时场次限制见 [功能覆盖](FEATURES.md) 与 [接口记录](API_NOTES.md)。

发行前还需提供 Android 正式签名与 Apple 发行配置。手动流程的 iOS `.ipa` 为未签名包，需要自行签名后才能安装到真机；产物在 Actions 保留 3 天。
