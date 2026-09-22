# 交给 apps-admin 的 KeepUp 四页配置更新提示词

请在 apps-admin 项目更新 KeepUp 已有配置记录并发布到既有 OSS 地址。先遵守该项目 AGENTS.md，核查当前记录、线上版本与 revision，保留未提交修改，不覆盖未知并发变更，不创建重复项目或版本，不修改其他 App 的配置，不接 Cloudflare。

完整目标 JSON：`/Users/xbingo/Developer/Projects/KeepUp/docs/config/keepup-iaap.1.0.0.json`。读取全部内容作为配置，不只保存广告或页面片段，不使用空广告的 initial 模板替代。

本次需要将 `iaaps` 更新为 `guide → launch → limited → vip` 四页并发布。此前“线上与本地一致、无需重发”的记录仅针对旧三页版本，不适用于当前四页修订。本 KeepUp 会话只修改本地客户端与文件，未修改 apps-admin、未发布本次四页配置。

目标与边界：

- KeepUp Bundle ID：`com.bestlife.keepup`；环境 `pro`；配置版本 `1.0.0`。
- 发布地址：`https://assets.xbingo.top/keep-up/pro/iaap/1.0.0.json`，对象名 `keep-up/pro/iaap/1.0.0.json`。
- 顶层保持 `system / ads / skus / iaaps`，不加外壳或加密包装；必须完整保存并导出 `system.isBanana=false`，不要丢字段或改值。
- `guide` 用于引导会员页，`launch` 用于启动会员页，`limited` 用于受限功能，`vip` 用于会员入口。按入口精确匹配，不保留旧 `final`、`limited_funcs` 或跨页回退。
- `launch` 和 `limited` 使用完整目标 JSON 中从原普通页继承的参数及商品；`guide / vip` 参数不变。四个商品及顺序不变；仅 `limited` 增加已确认的 `reward`，不填写价格。
- 总开关 `ads.enabled` 和 `splash / insert / reward` 的 `enabled` 全部保持 false。`gromoreAppId` 和三个 `mainland` 保持空字符串。不添加 `ads.policy` 或额外后台策略模型。
- 唯一 KeepUp AdMob App ID：`ca-app-pub-6174324407635385~7652648280`。
- 独立开屏、插屏、激励广告位分别为 `ca-app-pub-6174324407635385/7734118348`、`ca-app-pub-6174324407635385/4595065091`、`ca-app-pub-6174324407635385/1673388287`；不重建或复用其他 App 资源。
- 不添加 `isAuto`、地域路由、额外奖励次数、有效期、会员赠送或未确认价格。商品隐藏只移除页面 `iap.pids`，保留历史 `skus` 目录及类型。

客户端功能激励仅读取 `limited` 的既有 `reward { rewardId, insertId, count, hideGiveUpWhenNoAd }` 及 `hideFuncBtn / showGiveUp`，不回退其他页面。完整保留 `limited.reward`：`rewardId.oversea` 为 `/1673388287` 的完整激励广告位 ID，`insertId.oversea` 为 `/4595065091` 的完整插屏 ID，两个 `mainland` 均为空；`count=1`、`hideGiveUpWhenNoAd=false`，页面 `hideFuncBtn=false`、`showGiveUp=false`。一次成功观看仅放行本次功能；无广告可选择继续本次。全局及广告位开关仍关闭，因此发布该配置本身不会开启广告。通用广告时机由客户端入口衔接并受 `ads` 开关控制。

请沿用已有 JSON 保存、回显、导出和发布能力，确保四种类型不会被旧校验器丢弃。保存并发布后用动态 `?v=<当前毫秒时间戳>` 回读，核验 HTTP 200、`system.isBanana=false`、完整内容与目标 JSON 语义一致、页面顺序正确、无旧页面类型、无额外策略对象且广告全部关闭；动态参数不写入 OSS 对象名或持久 URL。报告发布版本、时间、URL、revision/并发处理及回读结果，分别标注后台修改、OSS 发布、客户端测试和真实交易/广告验收状态。

四个页面保留 `place` 场景名称：`guide=引导页`、`launch=冷启动`、`limited=功能拦截`、`vip=会员页`。客户端按 `type` 匹配入口，`place` 仅作场景元数据，不作为路由或广告开关；后台保存和导出时不能丢失。

本次完整 JSON 还包含四个页面的 `benefits`：依序为 `themes`（footer=30、timeInterval=5、hidePageControl=true）、`noad`（footer=50）和 `cloud`（footer=15）。请完整保存、回显、导出和发布，不能被其他 App 的 benefit 类型枚举过滤掉。该字段只控制页面模块、间距和主题轮播，不改变会员权益或开启广告。

请保留 `limited.reward.enabled=false`、`limited.reward.rewardId.enabled=false`、`limited.reward.insertId.enabled=false` 三个广告开关及原广告位 ID，不添加 `iaaps[].enabled` 页面开关。以后无需清空广告位即可停用；局部启用仍受 ads 总开关和对应广告位开关限制。缺省/null 兼容旧配置按 ID 判断的行为。

`cloud` 按正常 iCloud 模块展示，不加预告文案；CloudKit 同步实现状态单独记录，不改变会员授权。

客户端按 closeAlpha 原值显示关闭图标，不设最小透明度。reward.count 为本次放行所需的成功观看次数，支持任意正整数；0 不要求观看，重复回调不累计次数，关闭流程清空本次进度。当前 JSON 仍为 count=1。
