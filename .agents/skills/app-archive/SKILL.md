---
name: app-archive
description: 归档 KeepUp iOS 工程并导出签名 IPA。用户要求打包、archive、导出 IPA 或只生成 xcarchive 时使用；本 skill 只负责本地归档导出。
---

# KeepUp 打包

使用 KeepUp 的固定配置与归档脚本。先读 [config.env](config.env)，它是 project、scheme、Release 配置、签名团队、导出方式与 bundle identifier 的配置来源。默认导出 `release-testing` 测试分发 IPA，需要相应签名身份、描述文件及已登记设备；不将它描述为任意设备可安装的包。

从项目根目录执行：

```sh
.agents/skills/app-archive/scripts/archive.sh --dry-run
.agents/skills/app-archive/scripts/archive.sh
```

脚本默认创建独立的 `build/releases/KeepUp-时间戳-进程号/`，保留 `.xcarchive`、IPA、ExportOptions 和日志；DerivedData 留在项目内。`--dry-run` 只检查本地配置并打印命令，不调用 xcodebuild、创建输出目录或操作签名。

## 每次打包的可变项

- 默认同时归档与导出；用户只要归档时使用 `--archive-only`。
- 用户指定版本／构建号时传 `--marketing-version`／`--build-number`，只作用于本次构建。未指定版本时使用工程版本；未指定构建号时按北京时间自动生成 `yyyyMMddNN`，每日从 `01` 开始递增至 `99`，不修改工程文件。流水号在项目 `build/archive-build-numbers` 中原子占用，并避开本地历史归档的当日构建号；失败或取消后不回收，`--dry-run` 仅预览、不占号。保留编号目录以避免重复。
- 输出目录、archive 路径和额外 build setting 按需要覆盖；参数见 `scripts/archive.sh --help`。`--config` 接受受信任的本地 shell 配置文件，其他分发方式通过该配置选择，不直接修改默认配置。

## 本项目需要注意

- 使用 `KeepUp.xcodeproj`、`KeepUp` scheme 和 `generic/platform=iOS`，Bundle ID 为 `com.bestlife.keepup`，签名 Team 为工程现有的 `HWFBB53Y74`。
- 工程仅使用 Swift Package 依赖，沿用 `KeepUp.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`，包缓存为 `.build/SourcePackages`；不引入 PunchCard 的 Pods、Realm 或 NavigationBarKit 前置检查，不因打包升级依赖。
- 配置的自动签名允许 Xcode 更新描述文件。遇到账户、证书、设备或导出错误，保留日志并报告具体错误；不自动改团队、关闭签名、反复重试或把未签名构建当作 IPA 成功。

先按项目 AGENTS.md 的渠道规则理解请求：未指定渠道的“打包”先提供 `1. fir`、`2. fir + Store` 两个选项并等待选择。可用时使用交互式选项工具，让用户直接点选；发出选项后保持当前任务进行中，等待选择回复，不要立刻发送 final 结束本轮而使选项消失。没有交互式选项工具时，显示编号选项并等待用户回复。明确只要本地包时只归档导出。选择渠道后，依次使用本 skill 产出的准确 IPA／archive 路径调用 [fir-publish](../fir-publish/SKILL.md) 或 [store-publish](../store-publish/SKILL.md)，不重复询问已授权步骤。归档脚本本身只负责本地输出，不提交代码、推送、上传或通知；保留工作区现有改动，不自动切分支或清理。

归档、导出或校验失败就停止。成功后报告脚本输出的 bundle identifier、实际版本／构建号、archive、IPA 和日志路径；`--archive-only` 明确说明未导出 IPA。脚本会核对 archive 与 IPA 的身份和版本，并验证 ZIP 完整性；未运行真实签名导出时，不能把预演或替身测试结果写成真机安装验收通过。

维护脚本时，可在项目根目录运行 `python3 Tests/AppArchive/test_archive.py`。测试用替身替换 xcodebuild，实际执行 shell、plist 和 ZIP 校验，覆盖正常导出及失败停止；不操作签名账户。
