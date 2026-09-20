# 普通记录、步行统计与全局入口核查

更新：2026-09-20。对照本机 PunchCard 源码的实际调用链，归属 F17/F24；本次不是全 App 所有状态验收。

## 原版汇总 helper 不等于可达页面

- `PunchCard/Me/PCMeService.m:114` 的 `getCardDataList` 包含普通记录、步行、跑步和骑行的汇总模型，但次数和步数等写死为 `1000/10086`，全 App 源码未找到调用。
- `PunchCard/Me/PCMeViewController.m:125` 调用 `getMeDataWithType:`；第 152–185 行实际只显示 `moneyList`、`userSettingsList`、`commonList` 三组设置，不显示上述汇总模型。`PCMeItemTypeWeekStatis` 也只有枚举声明，没有生成或跳转入口。
- `Cards/RunCard/Services/BCRunService.m:204/224` 的累计公里方法确实计算记录总和，但未找到调用方；此前 KeepUp 运动统计是独立补充的真实数据功能，不宣称复刻原版月统计页。
- `Cards/CardDetails/Trends/PCCardTrendsViewController.m` 实际是文字与单张照片编辑页面，不能根据 Trends 名称认定为趋势统计页。

因此，本次不为普通记录或步行新增一张没有原版可达依据的全局汇总页。

## 已覆盖的真实统计入口

- 原版 `Me/Views/PCMeHeadView.m:152` 展示连续打卡天数，来源 `Base/Services/PCResultCardService.m:359`。KeepUp `ProfileView` 已使用 `RecordStatistics.streak`，按民用日期去重计算。
- 原版 `PunchCard/Views/BCPunchCardUnUnitView.m:171` 在无单位卡录入时展示“第 N 次”，来源 `PCResultCardService.m:329` 的已完成记录数量。KeepUp `ComposeEntryView` 已根据相同卡的记录数量展示下一次序号。
- 普通卡海报的次数、累计数量与体重目标鼓励语使用真实记录，不以 `getCardDataList` 的占位数字作为依据；本批单独补齐对应分支。

## 本批落地：我的相遇天数

原版 `Me/Views/PCMeHeadView.m:154` 显示“昵称 - 与你相遇的第 N 天”，来源 `Me/PCMeService.m:27–29` 对用户创建时间的计算。KeepUp 原来只显示静态欢迎语；现使用已有 `UserProfile.createdAt`，不修改数据库。

`ProfileDuration.dayCount` 以设备当前时区计算创建日到当前日的民用日期差并加一，创建当日为第 1 天，未来或无效创建时间显示第 1 天。界面定期刷新，午夜后能更新。原版用秒数除以 86400，KeepUp 使用日历日期差，避免夏令时造成一天按 23/25 小时计算的问题。

新增单元回归覆盖创建当天、午夜一分钟跨日、春季和秋季夏令时、时区差异、未来和无效时间，均已通过；中英文界面与重启显示已验证。集成验证详见[本批实现记录](ordinary-posters-profile.md)。

## 下一优先级：计步日内数据

这是真实可达而尚未覆盖的功能，不能被近 7 天总步数列表替代。

1. `Cards/CardDetails/PCCardDetailsViewController.m:82–84` 把计步详情路由到 `BCWalkStepDetailView`；第 143–146 行实际创建视图。
2. `Cards/CardDetails/Views/Walk/BCWalkStepDetailView.m:169–182` 显示距离、热量、活跃时长和小时步数柱状图。
3. `Cards/WalkCard/PCHealthDataService.m:115–150` 查询五分钟区间；`PCWalkCardService.m:150` 起创建并保存区间记录。
4. `Cards/CardDetails/Views/Walk/BCWalkTimeSlotService.m:15–39` 将区间步数汇总到小时；第 74–83 行的展示活跃时间仅累计步数大于 5 的区间时长。服务内另一处保存总时长的计算未使用这个阈值，后续应统一并说明估算口径，不能继承矛盾行为。
5. `PCWalkCardService.m:117/202` 的热量是 `步数 × 0.03` 固定估算，不是系统测量值。若补齐，应明确“估算”，统一详情、海报与时间线口径。

KeepUp 当前 `StepReading`、`StepRecord` 只有每天的步数、可选距离和测量时间。下一批需独立设计分段查询、可选样本持久化和展示；区分零步、未知及部分缺测，不把每日总量均分伪造曲线，也不拿当前体重推算历史热量。旧记录没有分段时保留缺测，实际传感器观察继续集中后置。

## 全局入口剩余范围

- **联系**：原版 `Me/PCMeViewController.m:256` 打开 `ContactUs/PCContactViewController`，其第 81–86 行复制对应联系账号。KeepUp 当前 `ProfileView.row` 仍显示待接入提示，后续使用独立客服配置，不复制旧产品 QQ 群或邮箱。
- **评分**：原版 `Me/PCMeViewController.m:280` 调用 `Base/Services/PCSystemService.m:50` 打开指定 App Store 产品页。KeepUp 仍为待接入提示，应与独立商店产品配置一起实现，不复制旧 App ID。
- **连续打卡徽章点击**：原版 `Me/PCMeViewController.m:86–97` 会提示连续天数及可兑换主题；KeepUp 目前仅显示天数，主题兑换提示归入主题权益批次。
- **会员、广告、启动配置与云账号**：沿用现有执行清单，不能因为目标、提醒等本地入口已可用而认定这些外部配置已完成。

以上核查保留真实缺口，排除未调用占位统计页；学习笔记与存储约定保持不变。
