# KeepUp

面向海外市场的独立 iPhone App。复用 PunchCard 的 UI 和图片资源，使用 SwiftUI 与 WCDB 建立独立实现。

- 最低系统：iOS 26.0。
- Bundle ID：`com.bestlife.keepup`。
- 首发语言：英文、简体中文。
- 独立数据、会员、云容器与发布配置，不导入 PunchCard 数据。
- 首发功能与 PunchCard 对齐；复用原版 UI、布局和图片资源，代码是否复用按实现需要决定。

## 当前阶段

正式 iPhone 工程已建立，完成第一条本地记录流程：选择日期 → 中间 + 入口 → 卡片列表 → 数字键盘/完成型打卡 → WCDB 保存 → 日历和时间线查看 → 删除。支持英文和简体中文；按 PunchCard 原版保持浅色外观。

已恢复原版 45 种卡片目录和 6 个分类；40 种普通卡可本地打卡，起床和体重专用流程已接通；计步、跑步、骑行仍待实现。资料填写和会员墙已复用原版资源、布局与交互，并接入本地资料保存。已补充个人信息列表、记录文字/单张照片与草稿、普通卡片详情及分享、14 套主题列表和预览。已补充普通运动卡的热量估算、食物换算和时间线当日热量汇总。已补充自定义卡创建/移除/恢复、固定待打卡、每周进度、本地提醒、未来待办、起床卡和体重目标。其余 UI 正在逐页还原，尚未完成全 App 的 1:1 验收。当前实现和后续范围见[工程基础进度](docs/foundation-status.md)。前期直接使用 WCDB，CloudKit 延后。`Prototypes` 中的代码仅用于技术验证，正式 App 不依赖原型源码。

## 运行

用 Xcode 打开 `KeepUp.xcodeproj`，选择 `KeepUp` scheme 和 iOS 26 或更高版本的 iPhone 模拟器，运行即可。首次打开需要解析 SPM 依赖。真机运行时在 Signing & Capabilities 中选择自己的开发者 Team。

本机验证环境为 Xcode 27.0、Swift 6 语言模式、iOS 26.5 模拟器，最低部署版本仍为 iOS 26.0。

```sh
xcodebuild -project KeepUp.xcodeproj -scheme KeepUp \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  -derivedDataPath .build/DerivedData \
  -clonedSourcePackagesDirPath .build/SourcePackages \
  -parallel-testing-enabled NO test
python3 Scripts/validate_localization.py
python3 Scripts/validate_configuration.py
```

工程文件已包含在仓库中，日常使用不需要生成工具。修改目录结构后如需重新生成工程，可使用现有 Ruby `xcodeproj` gem 执行 `ruby Scripts/generate_project.rb`；该脚本会重建工程设置，手动配置的 Team 等内容需自行保留。

## 文档

1. [项目决策与范围](docs/project-decisions.md)
2. [PunchCard 源码功能清单与服务依赖](docs/feature-inventory.md)
3. [建议架构、数据与全球化设计](docs/architecture.md)
4. [存储与同步验证报告](docs/persistence-validation.md)
5. [Core Motion 与 HealthKit 计步评估](docs/step-counting.md)
6. [工程基础进度与验证](docs/foundation-status.md)
7. [PunchCard UI 与资源复用](docs/punchcard-ui-reuse.md)
8. [资料填写与会员墙还原、验证记录](docs/profile-membership-restoration.md)
9. [记录内容、个人信息与主题进展](docs/details-profile-themes.md)
10. [自定义卡、固定卡、每周进度与提醒](docs/custom-cards-reminders.md)
11. [未来待办与起床卡](docs/scheduled-cards-wake-up.md)
12. [体重记录与目标](docs/weight-cards.md)
13. [预置 JSON 配置与维护](docs/bundled-configuration.md)

## 验证原型

[PersistenceSpike](Prototypes/PersistenceSpike/README.md) 验证 WCDB、Swift 6 隔离和 CloudKit 本地记录映射；不连接线上业务，不代表云同步已经完成。
