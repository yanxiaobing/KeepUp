# KeepUp IAAP 配置

当前完整交接配置为 `keepup-iaap.1.0.0.json`，与包内 `KeepUp/Resources/iaap.json` 同步。`keepup-iaap.initial.json` 是保留空广告对象的初始模板，本轮也统一为相同四类页面；发布时使用完整交接配置，避免以初始模板覆盖现有独立广告资源。

顶层沿用 `system / ads / skus / iaaps`，后台版本使用独立管理字段，不添加 `code/data` 外壳。

| 页面类型 | 客户端入口 |
| --- | --- |
| `guide` | 引导结束会员页 |
| `launch` | 启动会员页 |
| `limited` | 受限功能及其激励入口 |
| `vip` | 个人页会员入口、默认会员读取入口 |

页面数组顺序为 `guide → launch → limited → vip`。按入口精确查找，缺失页面不使用其他页面代替；不再接受旧 `final` 或 `limited_funcs`。本轮 `launch` 和 `limited` 继承原普通页的商品、关闭透明度、价格透明度和轮播参数，不添加奖励或价格。

- 商品顺序保持终身、年、季、月，全部使用 KeepUp 独立商品 ID；实际价格与订阅周期由 StoreKit 显示。
- 引导页参数保持原值，`guide / vip` 内容不变；客户端保留可见退出入口。
- 三份配置均明确设置 `system.isBanana=false`，保持用户指定值。
- 完整配置中的广告总开关与三个广告位开关均为 false，不含 `ads.policy`，仅 `limited` 配置页面 `reward`。初始模板的 `ads` 仍为空对象。
- 现有主题免费；iCloud 使用 cloud 模块展示，CloudKit 同步仍待实现。
- 不复用其他 App 资源，不接入 Cloudflare。

App 已接入 HTTPS OSS、缓存与包内兜底。本轮四页结构仅更新本地，尚未由本会话发布；旧线上三页与本地一致的回读记录属于修改前历史状态。请按 [apps-admin 更新提示词](keepup-apps-admin-update-prompt.md) 更新发布，并回读核验四页结构。

四个页面保留 `place` 场景名称：`guide=引导页`、`launch=冷启动`、`limited=功能拦截`、`vip=会员页`。客户端按 `type` 匹配入口，`place` 仅作场景元数据，不作为路由或广告开关；后台保存和导出时不能丢失。

### benefits 页面模块

四个页面均可设置 `benefits` 数组，按配置顺序展示。KeepUp 当前支持 `themes`（现有主题展示，主题仍免费）、`noad`（会员免广告说明）和 `cloud`（iCloud 展示模块）。`footer` 为模块下方间距，单位 pt，缺省为 0，范围 0–2000。`themes.timeInterval` 控制主题轮播秒数（0–3600，0 表示手动翻页），缺省沿用页面轮播时间；`hidePageControl=false` 显示主题页码，缺省隐藏。商品轮播仍由 `iap` 控制。

字段兼容 SmokingCount / QuitSmoke 的 `type / footer / items / timeInterval / hidePageControl`。`items` 当前仅解析和保留，未实现对应的 intro 模块；其他 App 的 `nav / intro / cyber / widget` 等类型不会渲染，也不会导致整个配置失效。缺少或 null 的 `benefits` 保持原来的 themes + noad 布局；显式 `[]` 隐藏全部模块。关闭、恢复和购买按钮不受该数组控制。该字段只控制展示，不改变 StoreKit 权益。

### IAAP 内广告 enabled

开关放在 `iaaps[].reward.enabled`（整段激励流程）、`reward.rewardId.enabled`（激励视频）、`reward.insertId.enabled`（成功激励后的插屏），不放在页面或商品上。false 停用并保留广告位 ID；缺省/null 沿用旧配置按 ID 判断的行为。页面广告同时受 `ads.enabled` 和对应全局广告位的 `enabled` 约束，局部 true 不能越过全局关闭。激励关闭后不会单独播放其后置插屏；只关闭 insertId 不影响激励视频。三个局部开关本次均为 false，等待统一广告策略确认。

当前四页 benefits 顺序为 `themes → noad → cloud`，cloud.footer=15。旧配置缺省布局仍保持 themes + noad；显式数组决定是否显示 cloud。

客户端按 closeAlpha 原值显示关闭图标，不设最小透明度。reward.count 为本次放行所需的成功观看次数，支持任意正整数；0 不要求观看，重复回调不累计次数，关闭流程清空本次进度。当前 JSON 仍为 count=1。

商品 titleType 读取配置：appstoreDesc 使用商店描述、desc 使用 SKU.desc、timer 显示当日剩余时间；不自行声称有限名额。iap.timeInterval=0 关闭商品自动轮播，正值按配置间隔执行，guide 与普通入口一致。
