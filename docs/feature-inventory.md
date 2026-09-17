# PunchCard 源码功能清单与服务依赖

盘点日期：2026-09-16。

参考仓库：`/Users/xbingo/Developer/Projects/PunchCard`。
参考提交：`62719feb927803f705023622ee3e12b69e7a8778`；盘点时工作区干净。

## 阅读方式与证据边界

下表是根据页面入口、服务、模型、工程配置和只读资源数据库整理的实现清单。没有运行原 App，也没有读取线上配置，因此不把“代码存在”当成“当前线上所有用户都能看到”。行为验收应在正式实现前逐模块补齐。

本地资源库有 **46 个 CARD 条目（包含 1 个自定义模板条目）**、**31 个 CARD_CALORIE 条目**、**14 个 CALENDAR_STYLE 条目**。这些是资源条目数，不是已验证的可见卡片或可用主题数。

## 功能清单

以下源码路径相对于 PunchCard 仓库根目录；相邻仓库链接方便本机复核。

| ID | 功能 | KeepUp 需覆盖的行为 | 源码依据 | 验收重点 |
| --- | --- | --- | --- | --- |
| F01 | 主导航与日历首页 | 日历、时间线、我的；统一打卡入口 | [PCTabbarViewController.m](../../PunchCard/PunchCard/Main/PCTabbarViewController.m)、[XBCalendarViewController.m](../../PunchCard/PunchCard/Calendar/Controllers/XBCalendarViewController.m) | 首次进入、返回今天、日期切换、空状态；复用原版 UI 和资源 |
| F02 | 卡片选择 | 最近、推荐、分类、搜索、自定义卡入口 | [PCPunchCardService.h](../../PunchCard/PunchCard/PunchCard/Services/PCPunchCardService.h)、[PCPunchCardViewController.m](../../PunchCard/PunchCard/PunchCard/Controller/PCPunchCardViewController.m) | 中英文搜索词、排序与历史使用记录 |
| F03 | 普通打卡 | 数值、时长、无单位等类型的录入与保存 | [PCPunchCardService.m](../../PunchCard/PunchCard/PunchCard/Services/PCPunchCardService.m)、[PCCardResult.h](../../PunchCard/PunchCard/RealmModels/PCCardResult.h) | 单位、精度、重复打卡规则和完成状态 |
| F04 | 补打卡与删除 | 对指定日期补记、删除记录并更新统计 | [PCResultCardService.h](../../PunchCard/PunchCard/Base/Services/PCResultCardService.h)、[PCResultCard.h](../../PunchCard/PunchCard/RealmModels/PCResultCard.h) | 归属日期与真实录入时间分开；删除关联数据和云端记录 |
| F05 | 自定义卡 | 选择形象、命名、选择单位 | [BCCreateCustomCardViewController.m](../../PunchCard/PunchCard/Cards/CustomCard/Controllers/BCCreateCustomCardViewController.m)、[BCCustomCardUnitsViewController.m](../../PunchCard/PunchCard/Cards/CustomCard/Controllers/BCCustomCardUnitsViewController.m) | 当前 1:1 阶段沿用原版“5 个汉字或 10 个字母/数字”布局限制；跨语言放宽须另行验收 |
| F06 | 常驻卡与每周目标 | 固定显示、移除设置、本周不同打卡日期的进度展示 | [PCCardTarget.h](../../PunchCard/PunchCard/Cards/TargetCard/PCCardTarget.h)、[PCCardTargetService.h](../../PunchCard/PunchCard/Cards/TargetCard/AlarmClock/PCCardTargetService.h) | 一周起始日、目标变更、取消目标不误删历史 |
| F07 | 提醒与闹钟管理 | 指定提醒时间、星期周期、统一管理 | [PCLocalNoticeService.h](../../PunchCard/PunchCard/Cards/TargetCard/AlarmClock/PCLocalNoticeService.h)、[PCNoticeManageViewController.m](../../PunchCard/PunchCard/Me/NoticeManage/PCNoticeManageViewController.m) | 权限拒绝、关闭目标、时区和夏令时变化 |
| F08 | 待办/日程卡 | 指定日期、描述、今日/过期/未来状态及完成 | [PCCardSchedule.h](../../PunchCard/PunchCard/Cards/ScheduleCard/PCCardSchedule.h)、[PCScheduleCardService.h](../../PunchCard/PunchCard/Cards/ScheduleCard/PCScheduleCardService.h) | 未完成和已完成的查询、跨日展示 |
| F09 | 起床卡 | 起床时间记录、目标与历史展示 | [PCEaryCardService.h](../../PunchCard/PunchCard/Cards/EaryCard/PCEaryCardService.h)、[PCResultCard.h](../../PunchCard/PunchCard/RealmModels/PCResultCard.h) | 用户选择时间与真实记录时间、补录 |
| F10 | 计步 | 实时步数、日内数据、目标、距离与热量展示 | [PCHealthDataService.m](../../PunchCard/PunchCard/Cards/WalkCard/PCHealthDataService.m)、[PCWalkCardService.h](../../PunchCard/PunchCard/Cards/WalkCard/PCWalkCardService.h) | 原版用 CMPedometer；KeepUp 按实时性和授权体验选 CM/HealthKit，见计步评估 |
| F11 | 户外跑步与骑行 | 准备、定位、开始/暂停/结束、轨迹、分段和结果 | [BCRunningResult.h](../../PunchCard/PunchCard/Cards/RunCard/Models/BCRunningResult.h)、[BCRunService.h](../../PunchCard/PunchCard/Cards/RunCard/Services/BCRunService.h) | 锁屏记录、GPS 漂移、异常中断恢复、单位切换 |
| F12 | 室内跑步 | 传感器记录、时长/距离、结果保存 | [BCRunningResult.h](../../PunchCard/PunchCard/Cards/RunCard/Models/BCRunningResult.h)、`PunchCard/Cards/RunCard/RunningInDoor/` | 室内距离计算和室外轨迹分开验证 |
| F13 | 运动设置 | 倒计时、语音、自动暂停、防误触锁定、常亮、地图显示等 | [BCRunSettingViewController.m](../../PunchCard/PunchCard/Cards/RunCard/Run_Setting/Class/BCRunSettingViewController.m) | 可选项按实际入口确认；语音素材需英文适配 |
| F14 | 体重与目标 | 体重记录、目标、历史、变化与 BMI 展示 | [PCWeightCardService.h](../../PunchCard/PunchCard/Cards/WeightCard/PCWeightCardService.h)、[PCWeightCardTarget.h](../../PunchCard/PunchCard/Cards/WeightCard/PCWeightCardTarget.h) | kg/lb 转换不改变原始数值；计算输入缺失处理 |
| F15 | 记录详情、文字与照片 | 编辑记录附加文字、照片和展示详情 | [PCCardTrendInfo.h](../../PunchCard/PunchCard/Cards/CardDetails/Trends/PCCardTrendInfo.h)、[PCCardTrendService.h](../../PunchCard/PunchCard/Cards/CardDetails/Trends/PCCardTrendService.h) | 模型存在 9 个图片字段，但 UI 上限仍需运行确认；这不是公共社交动态 |
| F16 | 时间线 | 按日期组织记录与内容，进入详情 | [PCTimeLineViewController.m](../../PunchCard/PunchCard/TimeLine/PCTimeLineViewController.m)、[PCTimeLineService.h](../../PunchCard/PunchCard/TimeLine/PCTimeLineService.h) | 排序、日期格式、删除后的刷新 |
| F17 | 统计 | 连续天数、累计次数/天数、步行和运动汇总 | [PCResultCardService.h](../../PunchCard/PunchCard/Base/Services/PCResultCardService.h)、[PCMeService.m](../../PunchCard/PunchCard/Me/PCMeService.m) | 部分旧 helper 包含占位值，真实展示口径需沿调用链核实，不能照搬占位数据 |
| F18 | 日历主题 | 主题列表、预览、选择与权益限制 | [PCSkinService.h](../../PunchCard/PunchCard/Skin/Service/PCSkinService.h)、`PunchCard/Skin/SkinDetail/` | 14 套资源配置与实际上线主题分别确认；英文标题和城市描述 |
| F19 | 分享与保存 | 将记录详情保存为图片并分享 | [PCCardDetailsSaveViewController.m](../../PunchCard/PunchCard/Cards/CardDetails/Share/PCCardDetailsSaveViewController.m) | 英文长文案、长图、地图快照、相册权限 |
| F20 | 个人资料 | 头像、昵称、性别、出生年、身高体重 | [UserInfoViewController.swift](../../PunchCard/PunchCard/Module/UserInfo/UserInfoViewController.swift)、[PCUserInfo.h](../../PunchCard/PunchCard/RealmModels/PCUserInfo.h) | 保留需要的计算参数；不共享旧资料和 Keychain |
| F21 | iCloud 数据 | 用户资料及打卡、目标、体重目标、记录内容的云操作 | [PCCloudCacheService.m](../../PunchCard/PunchCard/Base/Services/iCloud/PCCloudCacheService.m)、[PCCloudService.m](../../PunchCard/PunchCard/Base/Services/iCloud/PCCloudService.m) | 会员控制、首次恢复、离线修改、删除、账号切换；不能只验证上传 |
| F22 | 会员与恢复购买 | 主题、去广告、云服务权益；购买与恢复 | [IaapConfigsM.swift](../../PunchCard/PunchCard/Module/Iaap/IaapConfigsM.swift)、[IapService.swift](../../PunchCard/PunchCard/Module/Iaap/IapService.swift) | 本地默认含终身/季度 SKU；实际销售组合由远程配置影响，不直接复制旧产品 ID |
| F23 | 广告与激励入口 | 开屏、插屏、激励视频与会员免广告 | [GlobalAdService.swift](../../PunchCard/PunchCard/Swift/Advertise/GlobalAdService.swift)、[LaunchConfigM.swift](../../PunchCard/PunchCard/Launch/LaunchConfigM.swift)、[PCMeService.m](../../PunchCard/PunchCard/Me/PCMeService.m) | 可见入口受配置控制；无广告填充、失败和奖励到账分别验收 |
| F24 | 启动与基础设置 | 配置加载、资料引导、云账号状态、协议、联系、评分和版本 | [LaunchService.swift](../../PunchCard/PunchCard/Launch/LaunchService.swift)、[PCMeService.m](../../PunchCard/PunchCard/Me/PCMeService.m) | 网络失败可用性、海外文案和独立客服/协议地址 |

## 不据此新增的功能

- 没有在本次扫描的 App 源码与工程中找到 WidgetKit 扩展证据，不加入首版。HealthKit 原版未接入，但用户已允许将其作为计步替代方案评估。
- 暂不加入 Android、iPad 专属布局、Apple Watch、公共社区、排行榜或独立账号密码系统。
- 旧本地化枚举里出现其他产品模块名称、素材目录里出现图标，不等于存在对应可用功能。
- 旧 ImageEditor 壳文件不能证明完整滤镜/贴纸编辑流程；以详情分享实际可达能力为准。

## 服务与依赖处理

| 类别 | 原项目证据 | KeepUp 建议 | 接入条件/未决项 |
| --- | --- | --- | --- |
| 本地存储 | Podfile 中 Realm + FMDB；PCRMService、资源 database.db | WCDB 保存业务数据，预置定义可用带版本的资源导入 | 不迁移旧用户数据库；WCDB 原型报告见后文 |
| 私有云 | CloudKit 手动 CRUD + Realm 中的待处理队列 | 后续再接，当前直接存 WCDB | 不作为前期开发条件 |
| 远程配置与资源 | LaunchService 从 OSS 地址读取 JSON；包含广告、会员页面和 SKU 配置 | URLSession + Codable 读取一份 JSON，本地兜底，使用独立地址 | 接入时提供 URL 即可，不展开后端选型 |
| 内购 | SwiftyStoreKit + 收据验证 + 本地/云端权益表示 | StoreKit 2，权益以验证交易为依据 | 独立产品 ID；不能把可编辑的 CloudKit 会员字段当授权来源 |
| 广告 | 穿山甲/广点通及 Google Mobile Ads；已有海外分支 | 海外候选 Google Mobile Ads + UMP，独立广告位 | 服务商仍待定；按同意状态控制请求，先用测试广告位 |
| 统计 | UMCAnalytics / UMCCommon 和 PCAnalyticsService | 定义少量业务事件，通过接口接服务商 | 不复制旧 SDK 标识；厂商选择不阻塞本地功能 |
| 步数 | CMPedometer / Core Motion | 实时显示暂优先 CM；满足体验可换 HealthKit | 见[计步评估](step-counting.md)；需要真机，模拟器不验证真实步数 |
| 地图与定位 | 当前代码使用 MapKit，含旧坐标兼容逻辑 | MapKit + Core Location | KeepUp 无旧数据导入，不迁入历史坐标猜测逻辑；新数据记录坐标来源 |
| 提醒 | 本地通知封装 | UserNotifications | 不仅因为最低 iOS 26 就新增 AlarmKit 闹钟能力 |
| 照片与分享 | 系统权限、图片处理及详情分享 | PhotosUI、必要的相机桥接、系统分享与图片生成 | 原版实际可达操作先保留，避免按依赖清单误增加编辑功能 |
| 界面依赖 | Masonry、SnapKit、CYLTabBar、多个弹层/列表/动画库 | SwiftUI 与系统控件优先 | 无需整套迁入；具体效果确需第三方时单独评估 |

## 后续行为验收顺序

1. 先录制原 App 的主导航、各种卡片、补打卡和删除操作；补齐重复打卡、目标变更、统计边界。
2. 验证运动、语音、照片、主题及会员受限入口，不把有代码但不可达的页面加入范围。
3. 用同一组人工样例对比数据结果与 UI；复用图片、布局、颜色和交互，英文长度及安全区差异需单独验收。
4. 再验收中英文、单位、时区和权限失败场景。

盘点未请求原项目线上配置、未调用广告或内购、未访问用户云端数据。
