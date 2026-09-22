# Service / Loader / 商品详情对照

本轮以本机 PunchCard 为业务参考，并对照 QuitSmoke、SmokingCount 较新的封装；修改只在 KeepUp。不是将旧 UIKit、SwiftyStoreKit 或其他 App 的账号/商品/广告位整套复制。

## 已阅读的参考职责

- PunchCard `Module/Iaap/IaapService.swift`：会员判断、普通/受限入口和页面结果。
- PunchCard `Module/Iaap/IapContainerCell.swift`、`IapTimerView.swift`、`DayLeftTimerView.swift`：标题类型、商品详情与页面配置的组合、当日倒计时。
- QuitSmoke `Iaap/Iap/IapService.swift`、SmokingCount `Iaap/Iap/IapService+Product.swift`：按商品 ID 缓存详情、按集合查询准备/加载状态、可绕过缓存刷新、购买/恢复后刷新权益。
- QuitSmoke `Iaap/Advertise/GlobalAdService.swift`、`Reward/RewardService.swift`、`Reward/RewardGadService.swift`、`Insert/InsertGadService.swift`：全局资格、广告位路由、Loader 缓存与失效、预加载/展示分离、展示对象保活、奖励回调与关闭回调分离。
- QuitSmoke `Iaap/Skus/IaapOperateView.swift`：成功观看次数累计、失败/提前关闭后仍可重试、无广告按页面配置处理。

## KeepUp 本轮收敛

| 参考职责 | KeepUp 实现 |
| --- | --- |
| IAP 共享商品 map / loadingMap | `MembershipProductCatalog`，按 ID 合并缓存，并发重叠请求共享；失败保留已有详情，显式刷新返回缺失商品时只移除对应 ID |
| 商品预加载与页面查询 | App 按各页面 pids 并集预取，页面按自身顺序展示；预取不弹错误，页面失败可显式重试 |
| SKProduct 展示扩展 | `MembershipProductDetails` 统一 SK2 价格、周期、免费试用/首购价格描述；只有 Apple 判定符合首购资格才展示优惠 |
| 商品与购买选择 | 购买仍使用同一商品 ID；配置重排尽量保持已选 ID；价格来自 StoreKit，不写正式价格 |
| 详情刷新 | 页面返回前台可强制刷新详情；购买/恢复后重查首购资格；远程配置变化同步商品与权益目录 |
| 标题与轮播 | titleType 驱动 timer / appstoreDesc / desc；timer 取本地当天结束时间，不附加名额或折扣承诺；timeInterval=0 手动翻页，正值按原值轮播 |
| Reward Service | `AdMobRewardedAdProvider` 负责资格、预加载和展示；`RewardedAdController` 仍负责回调归一与奖励去重 |
| Reward Loader | `RewardedAdLoader` 按广告位缓存、合并加载、1 小时过期、单次消费；`AdMobRewardedAdLoader` 及其 loaded object 封装 SDK 请求/事件 |
| 激励页面预加载 | 进入功能激励页先预加载，点击复用加载或缓存；下一次观看可再次预加载；无填充按 hideGiveUpWhenNoAd 处理 |
| 多次激励 | 达到 count 后放行一次；提前关闭保留页面并可重试；取消整个流程清空进度；重复事件不重复计数 |
| 开屏 / 插屏 | 沿用现有 Controller / Loader 分离、缓存有效期、资格检查和展示互斥；没有为统一名字而重写已覆盖的逻辑 |
| 交易 Service | 保留 SK2 交易监听、验签、恢复、到期/撤销刷新及历史 SKU 权益识别；不复制旧版共享密钥收据验证和其他 App 的用户后台 |

## 明确边界

- 仅接独立 KeepUp AdMob；Gromore/国内路由仍空着，不拷贝参考项目的网络组合、硬编码测试/正式资源、method swizzling 或机器人上报。
- cloud 展示按已确认配置保留，CloudKit 实际同步尚未实现。
- 没有修改 apps-admin、OSS、App Store Connect 或 AdMob；本轮不等于真实购买、真实优惠资格、广告填充已验收。
- timer 的时间机制参考旧项目，但原项目“每天名额有限”的说法没有对应配额数据，因此不作为新规则加入。

## 验证

- `.build/reference-services-tests.log`：商品缓存、激励 Loader 和 Provider 针对性回归通过。
- `.build/reference-alignment-regression.log`：构建通过，266 项 Swift Testing（含默认跳过的线上用例）、9 项 XCTest 单元测试通过；会员页关闭及广告关闭时三个免费功能入口的 2 项 UI 回归通过。
- `.build/reference-carousel-tests.log`：最后的 0 间隔手动轮播修正构建通过，2 项定向测试通过。
- 配置校验与 `git diff --check` 通过。补测时工作区新增 Networking 源码尚未入工程，仅补齐已有源码/测试的 Xcode 引用，未更改该并行工作的网络协议实现。
- 以上是代码与模拟器验收，不代表真实 StoreKit 商品、优惠资格和真实广告填充验收通过。

## 独立 review 与修复验收

两位子代理分别只读审查 IAP/商品详情和广告 Service/Loader，一位子代理独立执行验收。审查发现并修复：

1. 商品集合部分重叠时重复加载及旧结果覆盖：改为按商品 ID 认领任务，仅 owner 写缓存；每次恢复后重新扣除已完成缓存。
2. timer 和三类首购说明缺少中英文：补全四个 key，配置校验现在检查这些动态本地化调用。
3. 商品刷新期间使用旧 Product 的价格：详情改为始终由当前 Product 生成，只单独缓存首购资格；刷新前清理资格。
4. 激励 SDK 不回调时重试一直复用挂起任务：Loader 独立 deadline 主动释放等待者，淘汰 generation，迟到结果不可污染重试。
5. 共享预加载在另一等待者消费缓存后误报取消：请求成功独立于缓存消费；单等待者取消不影响其他等待者，最后一位取消可立即重试。

修复后原审查代理复核了实现。独立复验日志 `.build/subagent-acceptance-fixed.log`：30 项单元测试、2 项 UI 测试通过，0 失败，配置校验和 diff 检查通过。真实 Product/首购资格、真实交易、真实广告填充及真机后台切换仍不在这次验收结论内。
