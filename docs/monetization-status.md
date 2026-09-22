# KeepUp IAAP、会员权益与广告进展

核查日期：2026-09-22。保留原有未提交的 `docs/config/` 和 `docs/admin-management-requirements.md`；本轮未修改 apps-admin，也未接入 Cloudflare。

## 客户端代码

- IAAP 已支持 `system / ads / skus / iaaps`、`guide / launch / limited / vip` 精确入口（默认会员读取 `vip`，缺页不跨页回退）、HTTPS 下载、缓存重启、原子写盘和包内兜底。Info.plist 已接入 `https://assets.xbingo.top/keep-up/pro/iaap/1.0.0.json`。每次网络请求添加毫秒时间戳 `v`，替换已有 `v` 并保留其他查询参数；磁盘缓存仍按原始 URL 匹配。错误响应不替换有效配置。
- 会员使用 App 级共享实例，监听 StoreKit 更新并在购买、恢复、前台、到期和撤销时刷新。已处理未验证交易、升级替换、并发刷新、旧商品请求及取消任务；商品加载失败不阻止权益检查。
- 历史会员商品目录独立于展示列表。包内四个历史 ID 保留；远程新增 ID 会累积进入磁盘历史目录。卸载重装无法恢复本机历史缓存，因此后台和后续包内目录仍须保留曾销售 SKU，仅从页面 `pids` 隐藏停售商品。
- 商品价格与订阅周期来自 StoreKit。未加载商品时禁止购买；远程配置变化不以旧索引购买新商品。移除没有实际依据的优惠倒计时、未实现的 iCloud 宣传和免费主题解锁说法，没有新增主题收费限制。
- 首批广告平台按用户决定接 AdMob。Google Mobile Ads `13.10.0`、UMP `3.1.0` 已加入锁定依赖，Info.plist 写入本轮核验的独立 App ID 和官方 SKAdNetwork 列表。GroMore 留空，腾讯暂不处理。
- AdMob adapter 已实现懒初始化、广告加载、展示、无填充与失败分类、奖励/关闭回调和取消隔离。UMP manager 提供显式准备和隐私选项方法，默认不请求广告、不弹表单。
- 开屏/插屏 SDK 结构已补齐：显式加载与展示、素材过期、无填充/失败、取消/超时和迟到回调；三种格式共享初始化和全屏互斥。App 级实例默认关闭且进入后台取消在途状态。
- 激励协调器覆盖成功、取消、失败、无广告、重复/迟到回调、会员变化和无回调超时。按 PunchCard 功能入口实现按次放行，新增 `RewardedFeatureAccess` 和原子 receipt 去重存储：体重目标、步数目标、提醒一次成功奖励仅放行当前操作，不赠送会员；当前总开关和三个广告位开关仍全部 false。

实现细节见 [IAAP 接入](iaap-client-integration.md) 和 [AdMob/激励接入](rewarded-ads-integration.md)。StoreKit 更新依据 [Apple Transaction.updates 文档](https://developer.apple.com/documentation/storekit/transaction/updates)，SDK 配置依据 [AdMob 官方接入文档](https://developers.google.com/admob/ios/quick-start)。

## 平台配置

| 平台 | 本轮核验/操作结果 | 尚未完成 |
| --- | --- | --- |
| App Store Connect | 已创建 KeepUp 独立 App（Apple ID `6814777647`，Bundle ID `com.bestlife.keepup`），以及下述会员商品 | 最终价格、销售地区、审核资料与真实交易验收 |
| AdMob | 独立 iOS 应用 KeepUp；App ID `ca-app-pub-6174324407635385~7652648280`；激励广告位 `KeepUp_iOS_Rewarded`，ID `ca-app-pub-6174324407635385/1673388287`；开屏 `/7734118348`、插屏 `/4595065091` 也已独立创建（同 publisher 前缀）；[广告位配置](https://admob.google.com/v2/apps/7652648280/adunits/1673388287/edit) | 商店关联/应用审核、隐私消息与真机广告验收 |
| GroMore | 未复用旧 Keep打卡资源 | 按用户决定留空 |
| 腾讯广告 | 未进行配置 | 按用户决定暂不处理 |
| OSS JSON | 实际 HTTPS 下载、配置解析与磁盘重启恢复已通过；每次请求带 `v` 时间戳 | 后续由 apps-admin 维护发布 |

Apple 裸名称 `KeepUp` 已被占用，独立 App 暂以 `KeepUp: Daily Habit Tracker` 创建草稿，未提交审核。先前仅由 App 列表显示 PackFlow 推断账号不匹配并不准确；继续检查创建入口后，已确认当前账号可以选择 KeepUp 的独立 Bundle ID 并创建 App。

独立会员商品如下，产品 ID 与包内及真实 OSS 配置一致。订阅属于 `KeepUp Premium` 群组（ID `22404173`），三个周期均设为级别 1，表示相同权益。四个商品已补充英语（美国）及简体中文显示名称和描述；订阅群组也已补齐这两种语言的显示名称。价格与销售范围保持未设置，没有提交审核。

| 商品 | 产品 ID | Apple ID |
| --- | --- | --- |
| 终身（非消耗型） | `com.bestlife.keepup.premium.lifetime` | [6814777874](https://appstoreconnect.apple.com/apps/6814777647/distribution/iaps/6814777874) |
| 年度（1 年） | `com.bestlife.keepup.premium.year` | [6814779228](https://appstoreconnect.apple.com/apps/6814777647/distribution/subscriptions/6814779228) |
| 季度（3 个月） | `com.bestlife.keepup.premium.quarter` | [6814779561](https://appstoreconnect.apple.com/apps/6814777647/distribution/subscriptions/6814779561) |
| 月度（1 个月） | `com.bestlife.keepup.premium.month` | [6814780197](https://appstoreconnect.apple.com/apps/6814777647/distribution/subscriptions/6814780197) |

AdMob 广告位已按用户要求创建。用户随后授权对齐 PunchCard：冷/热开屏及指定流程后的插屏时机，热启动后台间隔 30 秒，体重目标/步数目标/提醒三个入口一次成功奖励放行本次操作。平台默认 `1 Reward` 不是规则来源；客户端沿用 IAAP 页面 `reward.count`，当前实现仅支持一次放行，不赠送 VIP。`limited` 已配置激励及后续插屏；总开关和广告位开关关闭时仍不启用功能激励。所有开关继续关闭，不能将业务实现误认为正式投放已经开启。

`AppAdvertising` 已根据远程 typed config 同步 SDK 资格、会员检查和 UMP；`AdPresentationCoordinator` 衔接客户端通用广告时机及页面配置的奖励关闭流程，`RewardedFeatureAccess` 负责 receipt 去重及单次许可。入口 UI 接线已完成，最新测试结果见下面的 PunchCard 对齐验收记录；历史记录仅用于追溯。

## 本地验证记录

- Xcode 27 / iPhone 17 Pro 模拟器：201 项 Swift Testing + 9 项 XCTest 单元测试全部通过，其中本轮新增 IAAP 5、会员 10、激励 10、AdMob gate 2、UMP 7 项。
- 3 项会员 UI 回归通过：中文资料/会员流程、会员页关闭、引导完成进入首页；中文会员页截图已检查。原中文测试对昵称独立文本的过时断言改为验证实际 `profile.journey` 内容，商品不可用断言改为验证购买按钮禁用。
- 面向真机 `generic/platform=iOS` 的 Release 构建通过（`CODE_SIGNING_ALLOWED=NO`，未签名、未归档、未上传）；日志 `.build/monetization-release-build.log`。仍有原有 WCDB/头像裁剪代码的编译警告。
- 配置校验、本地化校验、Info.plist 格式检查和 `git diff --check` 通过。
- 首轮模拟器结果：`.build/DerivedData/Logs/Test/Test-KeepUp-2026.09.22_17-24-40-+0800.xcresult`；日志 `.build/monetization-verified-tests.log`。

- 接入真实 OSS URL 与时间戳后的补充回归：Swift Testing 报告 203 项通过（真实网络用例在默认离线测试中跳过），9 项 XCTest 单元测试通过，会员关闭 UI 测试通过；`.build/oss-platform-tests.log`，结果 `.build/DerivedData/Logs/Test/Test-KeepUp-2026.09.22_17-41-22-+0800.xcresult`。
- 单独开启真实网络的 IAAP harness：7 项测试全部通过，包含带时间戳的真实 OSS 下载和缓存重启。
- 最新无签名 Release 真机构建通过：`.build/oss-release-build.log`。

- 开屏/插屏补充回归：新增 12 项，全量 Swift Testing 报告 215 项通过（其中真实网络用例默认跳过），9 项 XCTest 单元测试和会员关闭 UI 通过；日志 `.build/fullscreen-ads-tests.log`，结果 `.build/DerivedData/Logs/Test/Test-KeepUp-2026.09.22_18-02-03-+0800.xcresult`。

- 开屏/插屏补充后的无签名 Release 真机构建通过：`.build/fullscreen-ads-release-build.log`。

## 验证边界

模拟器单元测试与 UI 回归用于验证客户端行为；真实 Apple 交易、退款/续订、UMP 表单和广告填充仍未完成。当前不应把“SDK 编译通过”或“回调模拟测试通过”标成真实广告验收通过。

后续真实交易验收需覆盖购买成功、取消、待批准、恢复、续订/到期、退款/撤销及停售后重装恢复。广告验收先使用官方测试广告，覆盖无填充、网络错误、取消、奖励回调与关闭顺序、重复回调、会员升级和奖励持久化，再验证正式资源。

## 完整配置交接

已提供完整交接 JSON 与可执行的 apps-admin 更新提示词，并同步包内及 initial 模板的页面结构。三份 JSON 均明确包含 `system.isBanana=false`。本轮页面顺序统一为 `guide → launch → limited → vip`；`launch / limited` 继承旧普通页参数与商品，`guide / vip` 保持原值。四个商品和独立资源 ID 不变；`limited` 已加入标准 `reward`，不新增价格或额外广告策略对象，全部广告开关保持 false。

客户端按入口精确查找，默认会员读取 `vip`；功能激励只读取 `limited` 的既有 `reward { rewardId, insertId, count, hideGiveUpWhenNoAd }` 和 `hideFuncBtn / showGiveUp`。缺页不串用其他页，`limited` 已配置 `reward`，当前广告开关关闭，因此功能仍免费直达。新远程若包含旧 `final / limited_funcs` 会被拒绝并继续使用有效配置或包内兜底，历史 SKU 缓存保留。

此前 `.build/iaap-policy-removal-remote.json` 的 HTTP 200 回读确认的是旧三页配置与当时本地一致，仅为历史记录。当前四页修订尚未由本会话发布，需要 apps-admin 更新发布后重新回读核验；本会话不修改后台或 OSS。

最新四页修订的验证见文末；此前记录仅作历史追溯。当前四页配置尚未发布。

## 历史：PunchCard 对齐验收（2026-09-22 19:10）

- Swift Testing 报告 248 项通过（真实 OSS 网络用例默认跳过 1 项），另有 9 项 XCTest 单元测试通过。当时版本包含强类型广告配置、15 项广告编排测试、按次许可去重/持久化测试、真实终态等待及 UMP 更新超时测试。
- 3 项 UI 回归通过：会员关闭；完整引导、会员关闭后进入首页及重启；广告关闭时三个功能入口直接打开并正常返回。
- 测试日志：`.build/punchcard-ad-policy-tests.log`；结果：`.build/DerivedData/Logs/Test/Test-KeepUp-2026.09.22_19-08-50-+0800.xcresult`。
- 全屏广告加载默认 3 秒上限；UMP 信息更新网络阶段 8 秒上限，用户操作表单不设超时。仅开启热启动时也会在真实机会准备 UMP；隐藏引导会员页后仍保留引导结束事件。
- Review 修复异步页面回调的上下文检查，导航离开取消排队流程，迟到奖励不能重新打开旧页面；成功奖励必须等真实广告关闭、后续插屏终结，再消费匹配的一次性许可。
- 平台资源本轮未新增或修改；当时新增的本地字段未发布 OSS，现已删除。`profile.ad` 的支持性观看广告入口仍为原占位提示，本轮完成的是上述三个按次放行入口。真实广告/UMP 和真实 StoreKit 验收仍未完成。

- 当时版本的真机目标 Release 构建通过（`generic/platform=iOS`、`CODE_SIGNING_ALLOWED=NO`），日志 `.build/punchcard-ad-policy-release.log`。未归档、未签名、未上传。仍有原头像裁剪隔离警告，以及 Release 下 UI 测试专用分支永不执行的编译提示。

## 历史：移除额外策略对象后的验证（2026-09-23）

- Swift Testing 报告 252 项通过（真实 OSS 用例默认跳过 1 项），另有 9 项 XCTest 单元测试通过。包含页面 reward 协议往返、类型/资源/开关校验、limited_funcs → final 回退、旧策略对象无效、页面插屏不回退通用广告位等回归。
- 3 项 UI 回归通过：会员页关闭、引导完成及重启、广告关闭时步数目标/体重目标/提醒直接进入。日志 `.build/iaap-page-ads-tests.log`，结果 `.build/DerivedData/Logs/Test/Test-KeepUp-2026.09.23_00-01-53-+0800.xcresult`。
- 当时的旧三页 JSON 与动态 v 回读的线上 JSON 完整语义一致，当时无需重发；此结论不适用于后续四页修订，四页版本仍待发布。

- 无广告降级按钮遵循页面最新 `hideGiveUpWhenNoAd` 值；最终页面回归再次通过（`.build/iaap-page-ads-ui-final.log`）。最终真机目标 Release 构建通过（`.build/iaap-page-ads-release.log`，未签名、未归档、未上传）。配置和本地化校验、diff 检查均通过；真实广告和交易验收状态不变。

## 四入口及 system.isBanana=false 验证（2026-09-23）

- 256项Swift Testing通过（1项真实网络用例默认跳过），9项XCTest单元测试及3项UI回归通过。日志`.build/iaap-four-entries-tests.log`。包含精确入口隔离、旧缓存历史SKU保留和旧远程页面不覆盖新配置。
- 无签名Release构建通过，日志`.build/iaap-four-entries-release.log`；未归档、未上传。配置、本地化与diff检查通过。
- 三份JSON均为guide/launch/limited/vip，system.isBanana=false；本次新配置尚未发布，真实交易和广告验收状态不变。

## limited 广告配置补充（2026-09-23）

仅修改配置、说明及对应校验：limited.reward 使用 KeepUp 独立激励 `/1673388287` 与插屏 `/4595065091`，count=1、hideGiveUpWhenNoAd=false；页面 hideFuncBtn=false、showGiveUp=false。三份 JSON 同步，system.isBanana=false 与四页顺序不变，总开关和广告位开关仍关闭。配置定向校验通过；未重跑全量测试或构建，未发布 OSS。
