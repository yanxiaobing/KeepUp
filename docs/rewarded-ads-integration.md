# KeepUp 广告激励接入状态

## 已核查的工程

初次核查时，工程没有广告 SDK 依赖、SDK 初始化代码、广告位 ID 或 Swift 广告播放入口。已有「观看视频广告」「会员无广告」本地化文案不代表已接入广告。初始 IAAP 配置的 `ads` 为 `{}`；历史 initial 文件保留，当前包内和待发布完整配置已记录关闭的广告资源；此前额外加入、未发布的 `ads.policy` 已删除。

主任务浏览器核查：AdMob 全应用列表只有旧「Keep打卡」（Store ID `1475058682`）和两款吸烟 App，没有 KeepUp；穿山甲存在旧「Keep打卡」，尚无可确认的 KeepUp 独立资源；腾讯广告会话失效。这些旧应用的商品或广告位不能用于 KeepUp。这是初次平台核查结果。后续已按用户选择创建并核验 KeepUp 独立 AdMob App，App ID 为 `ca-app-pub-6174324407635385~7652648280`，并写入 Info.plist。随后按用户要求创建并核验独立激励广告位 [KeepUp_iOS_Rewarded](https://admob.google.com/v2/apps/7652648280/adunits/1673388287/edit)，广告位 ID 为 `ca-app-pub-6174324407635385/1673388287`。平台默认的 `1 Reward` 仅为占位元数据，不代表正式业务奖励规则，不能据此发放奖励。当前已实现按次放行 ledger，placement 由远程强类型配置决定；由于总开关和所有广告位开关为 false，实际 placement 仍为空。GroMore 保持空白，腾讯不处理。

## 本次客户端结构

`RewardedAdController` 是可注入、MainActor 串行运行的单会话协调器。无参默认构造仍使用禁用 provider/ledger。App 通过 `AppAdvertising` 注入 AdMob provider、UMP gate 及 `RewardedFeatureAccess` 的正式按次放行 ledger；当前全部广告开关关闭，因此不加载广告、不发放奖励。开启业务必须同时满足：

- 已核实属于 KeepUp 的 provider 和独立广告位。
- 有效 IAAP 页面 `reward` 配置，以及实现按次放行的 ledger。
- 会员的 `canShowAds` 和隐私授权；任一条件不满足即关闭入口并取消在途请求。

每次展示生成一个 UUID。当前请求才接受回调；重复 earned、结束后的回调、取消后回调、上一请求的迟到回调都不能重复发奖。首次 earned 后在该次展示关闭前仍保持 busy，避免开第二个广告。关闭、失败、无广告均不等于 earned。

用户本轮已授权对齐 PunchCard：体重目标、步数目标、提醒三个入口支持一次成功奖励放行本次操作，不赠送 VIP、会员时长、可积累余额或跨次解锁。`FeatureRewardLedger` 使用 `JSONRewardReceiptStore` 原子写入去重 receipt；只有写入成功，才在同一个 MainActor 同步调用中记下当前请求的瞬时许可。必须同时收到 earned 与真实 SDK closed，且 request ID/feature ID 匹配，才能一次性 consume。持久化失败或损坏 receipt 文件安全拒绝奖励；崩溃重启不恢复中断操作或瞬时许可，不会将 receipt 当永久功能解锁。

取消、失败、无填充、超时或仅关闭都不授予许可。重复 earned、重复 close、迟到事件及再次 consume 均不能二次放行。所有开关关闭时保留原免费入口；开启后仍提供可见关闭/放弃入口，不强制观看。

## SDK adapter 事件约定

adapter 独占 SDK 对象并保留每次展示的 request ID；SDK 不能自行发放奖励。所有回调转发至 MainActor：

| 事件 | 协调器行为 |
| --- | --- |
| presented | 标记展示中 |
| rewardEarned | 只调用一次 `grantOnce` |
| closed | 最终终结会话，未 earned 则取消 |
| failed | 未 earned 时失败，不奖励 |
| unavailable | 无填充，不奖励 |

`closed` 指 SDK 的奖励判定已经完成，**不能简单照搬页面 dismiss**。Google 自有广告会先 earned 后 dismiss，但中介广告顺序由第三方 SDK 决定；如第三方 SDK 允许 dismiss 后 earned，adapter 必须保留会话到最终判定，再按 earned → closed 顺序转发。不得自行以短延迟猜测奖励成功。参考 [AdMob iOS 激励广告官方文档](https://developers.google.com/admob/ios/rewarded)。

会员升级、隐私撤回、配置切换和用户取消先使请求失效，再调用 provider.cancel；即使 cancel 同步触发 SDK 回调也不能误发奖。协调器提供可配置的 120 秒技术超时，SDK 不回调时终结会话并允许重试；已奖励后超时不重复发奖。AdMob provider 已实现对象清理；真机验收仍需核实实际加载/展示耗时与终结事件。

## 测试与后续验收

`RewardedAdTests` 使用注入 provider/ledger，覆盖成功、重复 earned、取消、失败、无广告、旧请求迟到回调、会员/隐私变化、配置失效、ledger 失败、无回调超时、旧超时隔离以及多次独立展示。它证明协调器状态和去重行为，**不代表真实 SDK 或真实广告验收完成**。

独立广告位已创建。先前业务接线的全量单元测试和 3 项 UI 回归记录见 `monetization-status.md`；此次改用既有页面奖励协议后的测试由主任务补充。AdMob 隐私消息、真实 UMP 表单、官方测试广告事件顺序及正式广告填充另行验收。平台默认 `1 Reward` 不作为客户端奖励来源；功能奖励读取页面 `reward.count`，按配置累计成功观看次数，达到 count 后一次性放行当前操作；重复回调不重复计数。

## AdMob 实际 adapter（后续确认）

用户已确定先接 AdMob，GroMore 留空。新增 `AdMobRewardedAdProvider.swift`，使用官方 GoogleMobileAds SDK API；构造没有网络副作用，只有实际启用的业务机会才初始化。有效 App ID、已许可的隐私状态、有效奖励配置与可展示界面都满足后才初始化并请求广告。SDK 初始化使用 MainActor 共享任务等待完成，避免并行重复初始化；加载完成后再次检查隐私状态和请求身份。

- 官方 SPM：`https://github.com/googleads/swift-package-manager-google-mobile-ads.git`，本次核验 tag `13.10.0`，product `GoogleMobileAds`；仓库 manifest 自带 UMP 包依赖。
- Info.plist：设置 KeepUp 独立的 `GADApplicationIdentifier`，按 [Google 官方初始化指南](https://developers.google.com/admob/ios/quick-start) 维护 `SKAdNetworkItems`。App ID 与广告位 ID 不是同一个值。
- Swift API：`MobileAds.shared.start`、`RewardedAd.load(with:request:)`、`Request`、`FullScreenContentDelegate`、`present(from:)`，已根据 [官方激励指南](https://developers.google.com/admob/ios/rewarded) 核验。
- 隐私：现有本地隐私协议不自动等于广告同意。调用方必须在适用地区完成 UMP/广告同意处理后才使 `privacyAllowsAds` 为 true；若使用 ATT/IDFA，另按实际用途完成授权与用途文案。当前奖励入口仍关闭，代码没有擅自请求 ATT，也没有把隐私协议接受映射成广告同意。
- 展示：可注入具体 scene 的 presenter，默认只接受唯一前台 scene 的 key window 顶层控制器；拒绝模糊多窗口或正在转场的控制器。
- 错误：Google 的 noFill 映射 unavailable，加载/展示异常映射 failed。回调同时核对请求 UUID 和广告对象，取消后的加载结果和奖励回调被丢弃。
- 取消：SDK 没有公开强制关闭全屏广告的方法；取消使本次奖励回调失效并取消加载任务，已经可见的广告仍使用 SDK 自身关闭按钮，不能强制 dismiss 用户的其他页面。

本 adapter 仅适用于当前无中介 SDK 的 Google 广告路径。引入中介前必须单独实现其 dismiss/earned 的最终判定顺序。平台 ID 配好仍不等于可以开启入口：正式奖励 ledger 和按次放行规则现已实现，但广告开关、会员资格、适用隐私同意与真实验收仍需分别满足。`AdMobRewardedAdProviderTests` 验证缺失配置和隐私拒绝时不会继续执行；此测试不发送网络请求，不代替真实 SDK 测试广告验收。


## UMP 同意流程结构

新增 `AdMobConsentManager`，构造时不请求网络、不弹窗，默认 `canRequestAds=false`。`AppAdvertising.prepareConsentIfNeeded()` 在会员检查完成、配置有效、隐私协议接受且页面无遮挡时显式调用 `prepare(from:)`，顺序执行 consent info update 和 `ConsentForm.loadAndPresentIfRequired`；两步成功后才读取 UMP 的允许广告状态。任一步失败或任务取消均保持关闭，不自行信任本地缓存同意值。此流程依据 [UMP 官方文档](https://developers.google.com/admob/ios/privacy)。

个人页已根据 `privacyOptionsRequired` 提供隐私选项入口并调用 `presentPrivacyOptions(from:)`；用户变更期间广告关闭，结束后重新读取 SDK 状态。并发流程会返回 busy，避免重复弹窗。真实接入时需观察 `canRequestAds`，同时更新激励协调器 eligibility 和 adapter 的 privacy closure。

App 级接线现由 `AppAdvertising` 统一准备 UMP 并同步授权状态；当前广告总开关关闭，不触发准备或表单。AdMob Privacy & messaging 的真实消息配置、地区分支和真机表单验收尚未完成。按次放行 ledger 已实现；最新入口 UI 接线与测试由主任务统一验收。


## 开屏与插屏（2026-09-22 补充）

用户已授权参考 PunchCard 的业务策略实现，同时要求所有广告继续关闭。已在同一 KeepUp 独立 iOS 应用下创建：

| 格式 | 广告单元名称 | 广告单元 ID |
| --- | --- | --- |
| 开屏 App Open | KeepUp_iOS_AppOpen | `ca-app-pub-6174324407635385/7734118348` |
| 插屏 Interstitial | KeepUp_iOS_Interstitial | `ca-app-pub-6174324407635385/4595065091` |
| 激励 Rewarded | KeepUp_iOS_Rewarded | `ca-app-pub-6174324407635385/1673388287` |

三类 ID 已记录到 Info.plist 自定义 `KeepUpAdMob*AdUnitID` 键；ID 存在不代表广告启用。后台频次上限仍为平台默认，客户端未赋予其正式投放含义。没有复用其他 App 资源；GroMore 保持空白。

[开屏广告位](https://admob.google.com/v2/apps/7652648280/adunits/7734118348/edit) · [插屏广告位](https://admob.google.com/v2/apps/7652648280/adunits/4595065091/edit)

客户端新增 `AdMobFullScreenAdController`，开屏和插屏各持有独立实例。显式 `load()` 与 `present()` 分开，构造不请求广告；前后台业务机会交给 `AdPresentationCoordinator`，只有远程启用且会员、隐私、场景资格成立才可加载。`updateEligibility` 联动会员和隐私状态。当前关闭配置映射为空广告位，进入后台取消在途状态。缓存有效期用于 SDK 素材有效性，不是业务频控：开屏 4 小时、插屏 1 小时；过期素材不会展示。

三种格式使用 `AdMobRuntime` 单次初始化与 `FullScreenAdGate` 全局展示互斥。取消一个已经显示的广告不强制关闭 SDK 界面，锁一直保留到 SDK 确认关闭/展示失败，防止其他格式覆盖；旧请求或重复终止回调不释放新请求的锁。通用业务时机由客户端入口衔接并受 `ads` 总开关与广告位开关控制；实际投放仍需配置启用、UMP 允许及真机测试广告验收。

参考：[Google 开屏指南](https://developers.google.com/admob/ios/app-open-ads)、[Google 插屏指南](https://developers.google.com/admob/ios/interstitial)。

本轮新增 12 个 `FullScreenAdTests`，验证默认关闭、仅加载不展示、两个缓存过期边界、跨格式互斥、可见广告取消、权益撤回、无填充/失败、迟到回调、初始化阶段取消、调用者取消传播与加载超时。完整工程采用 Swift 6 严格并发检查；加载结果协议为 `@MainActor` 且要求 `Sendable`，不使用 unchecked 绕过。

全量单元测试及会员关闭 UI 回归通过（2026-09-22 18:02），日志 `.build/fullscreen-ads-tests.log`；默认离线测试跳过真实 OSS 用例。这些测试使用假广告对象，不代表真实 SDK 广告填充或真机展示通过。

## PunchCard 业务接线与既有 IAAP 协议

`AppAdvertising` 将广告资源映射统一提供给三个广告实例。通用冷启动开屏、后台停留至少 30 秒后的热启动，以及引导/启动会员页关闭后的插屏由客户端入口衔接，并检查 `ads` 总开关、具体广告位开关、会员、隐私和场景资格，不再要求新增后台策略对象。开屏/插屏加载最多等待 3 秒；冷启动机会失效后，不在首页补弹迟到广告。

功能激励只读取 IAAP 的 `limited` 页面，不跨页回退；读取既有 `reward { rewardId, insertId, count, hideGiveUpWhenNoAd }`、`hideFuncBtn` 和 `showGiveUp`。`rewardId`、`insertId` 必须解析为 KeepUp 独立资源。奖励数量来自有效的页面 `count`，当前实现只支持一次成功放行本次功能；不从广告平台默认值推导。未配置页面 `reward` 时不启用功能激励；资源 ID 本身不授予功能限制或广告资格。

`RewardedFeatureAccess` 管理体重目标、步数目标、提醒的当前请求及一次性许可。会员无需广告；配置/会员/隐私变化和进入后台取消在途流程。成功必须先收到 earned，再收到真实 SDK closed，后续插屏使用页面 `reward.insertId`；插屏流程终结后再消费当前许可并进入功能。不存在有效后续插屏配置时不补充广告。

包内、完整交接和初始模板均设置 `system.isBanana=false`，页面已统一为 `guide → launch → limited → vip` 四页。`launch` 保留普通页参数与商品；`limited` 增加既有独立激励/插屏广告位、count=1、hideGiveUpWhenNoAd=false，并设置hideFuncBtn=false、showGiveUp=false。不新增价格，完整配置的广告开关仍全为 false。三个功能保持免费直达，未开启正式投放。

此前真实 HTTPS 回读确认一致的是旧三页版本，不能作为当前四页已发布的证明。本次四页更新仅在本地，需 apps-admin 使用完整交接 JSON 更新发布；本 KeepUp 会话未修改后台或 OSS。配置仍不含额外广告策略对象。

此前测试记录对应历史实现。最新四页结构按入口精确查找，缺页不串用其他页；新远程旧类型会被拒绝并使用有效配置或包内兜底，历史 SKU 缓存保留。此次修订的测试与构建结果待主任务补充。真实广告播放、奖励发放、UMP 表单和真实 StoreKit 交易均未验收完成。

UMP 信息更新的网络等待上限为 8 秒；超时/取消不会因迟到回调再弹同意表单。用户正在操作的真实 UMP 表单不设自动完成时限。无有效广告配置不准备 UMP。无广告时的“继续本次”属于显式降级，不写入奖励许可，其展示遵循既有页面参数，同时保留可见退出入口。

### 冷启动会员入口修正

`launch` 会员页与广告开关、UMP 广告授权和开屏填充解耦。已有资料的非会员冷启动，在权益初始化完成且 launch 有可展示商品时请求一次会员页；有开屏广告时等待其流程结束，没有广告或广告失败时仍可展示。后台失效的冷启动机会不补弹。广告配置刷新不会撤销已请求的会员页。首次引导仍使用 guide，热启动不重复请求 launch。该行为使用 KeepUp 当前封装实现，并非原参考工程服务的整套迁移。
