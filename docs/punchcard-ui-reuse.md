# PunchCard UI 与资源复用

日期：2026-09-16。

## 产品约束

KeepUp 复用 PunchCard 的 UI 和图片资源。独立工程、SwiftUI 重写和“不强调代码复用”均不代表重新设计视觉。中英文适配在原版布局基础上完成。

## 本次对应关系

| 页面 | PunchCard 实现依据 | KeepUp 对齐内容 |
| --- | --- | --- |
| 主导航 | `Main/PCTabbarViewController.m`、`PCCalendarTabbarButton.m` | 时间线在左、日历/打卡在中、我的在右；中间选中时显示原版 + 图片，再点打开选卡 |
| 日历 | `Calendar/Views/XBCalendarBackgroundView.m`、`XBCalendarHeadOperateView.m`、`Controllers/XBCalendarCardListViewController.m` | 默认起始点插画、蓝底、黑色月份栏、紧凑白色周/月历、原版日期色、灰色记录区 |
| 日历记录 | `Calendar/CalendarCardItems/XBCalendarCell.m`、`XBCalendarNormalCell.m`、`XBCalendarAddPastCell.m` | 三列票卡、原版人物形象、彩色标题条、补打卡图标 |
| 选卡 | `PunchCard/Controller/PCPunchCardViewController.m`、`Views/BCPunchCardListView.m` | 搜索、横向分类、原图图标、80 点列表行和右侧箭头 |
| 数值录入 | `PunchCard/Views/BCPunchCardKeyboardView.m` | 底部弹层、卡片图标与数值、7/8/9 起始的数字键盘、原版删除图、橙色打卡按钮 |
| 时间线 | `TimeLine/PCTimeLineViewController.m`、`Views/PCTimeLineCell.m` | 原版空状态插画、日期分组、左侧运动图、行式记录与时间 |
| 我的 | `Me/Views/PCMeHeadView.m` | 原版图案头图、跨越头图的圆头像、橙色连续天数标签、平铺设置列表 |

原版路径相对 `/Users/xbingo/Developer/Projects/PunchCard/PunchCard`。

## 2026-09-16 第二轮：原版尺寸与页面结构

- 日历：原版 `34 + 136 × 屏宽 / 375` 顶图高度，44 点月份栏、15 点两侧留白；默认周历、周/月状态持久化，滑动翻页；删除自行添加的前后月箭头、今天的虚构添加卡和空白说明文案。历史日期仍可补打卡。
- 底栏：49 点内容高度，原图标、10 点标签，中央按钮按原图尺寸与上移量显示。
- 推荐页：恢复体重/跑步/骑行三张原图大卡、“更多”分隔标题及双列快捷卡；分类恢复推荐、健身、球类、生活、饮食健康、最近；搜索与 80 点列表行按原约束布局。
- 录入：替换原生浮动 sheet 为全屏遮罩上的贴底面板；复用闹钟与退格图，按屏宽缩放 94 点头部、69 点键盘行、55 点按钮；普通数值键盘不再增加原版没有的小数键和备注框。完成型卡恢复“第 N 次”与大号卡名。
- 我的：恢复头像/性别图/连续天数、会员和广告、目标与闹钟、评价/联系/版本三组原版入口和 50 点缩放行高；语言入口移至设置。
- 时间线：白色运动图、40 点缩放图标、原文字尺寸与间距；导航栏使用原版主题色。
- 原版 Info.plist 明确指定 Light，KeepUp 本轮也固定浅色外观。英文长文案在原有结构内压缩或滚动。

## 资源与数据

直接复制 304 个原版 imageset，保留 PNG 字节、尺寸、缩放倍率与名称。来源及 SHA-256 见 [资源清单](punchcard-resource-manifest.json)。没有复制广告/内购标识或生产配置。

从原版只读 `Resource/database.db` 的 CARD 表提取 45 种卡片名称、单位与资源映射，保存到 `Resources/cards.json`，由 `Domain/OriginalCatalog.swift` 读取。保留之前六张卡的持久化 ID，通过 WCDB `insertOrIgnore` 补齐目录，不清除已有记录。

40 种普通卡支持本地记录；计步、起床、跑步、骑行、体重须使用原版专用流程，目前点击明确提示未接入，未用普通输入冒充传感器或 GPS。

## 原版运行与截图对照

PunchCard 原工程使用 x86_64 模拟器构建，解决旧 Realm arm64 静态库只有真机架构的问题。补齐模拟器签名后，可通过原版“不使用 iCloud 继续”进入本地模式并查看会员墙。

资料页使用 `.build/ReferenceUIHarness` 内的独立源码副本，增加 `-reference-profile` 参数直接展示原版 `UserInfoViewController`，仅改变参考包的入口，不改资料页代码、不写资料，也不修改 PunchCard 工作区。原工程保持干净。

`.build/ui-review/Reference-*.png` 为原版截图；`KeepUp-*.png` 为新实现截图。早期以 `PunchCard-` 开头的截图是 KeepUp 的旧轮次截图，不应当作原版参考。

## 2026-09-16 第三轮：资料填写与会员墙

- 资料填写：恢复两步横向分页、原版插画及坐标、PingFang 字体、昵称输入与清除、男女选择、头像菜单、拍照/相册、固定正方形裁剪、出生年/身高/体重标尺、资料确认弹窗。
- 裁剪通过官方 SPM 包 TOCropViewController 3.2.0 接入，使用包自带本地化资源，保持原版正方形裁剪配置；SwiftUI 外层通过 UIViewControllerRepresentable 使用。无 SnapKit/Realm/广告 SDK 依赖。
- 本地资料：WCDB schema 2 新增 profile 表，保留 cards/entries；头像以压缩 JPEG 保存在同一数据库。首次保存之后进入会员引导页，重启不再重复填写；个人设置可重新打开填写页，取消时不保存修改。
- 会员墙：原版 13 个城市主题轮播、城市颜色、逐字变号渐变文字、无广告/iCloud 权益、底部渐变、商品横向分页、当天倒计时、继续按钮动画、恢复入口、引导页放弃优惠入口。
- `Resources/membership.json` 保存独立 KeepUp 商品 ID 和界面参数；价格来自 StoreKit，未提供商品时显示暂不可用。当前 ID 是预留值，需在 KeepUp 的 App Store Connect 配置实际商品后验证购买/恢复。没有复制 PunchCard 产品 ID，也没有把按钮点击直接视为会员购买成功。
- CloudKit 仍按项目约定延期，权益展示沿用原版页面结构；当前数据只保存在 WCDB。

## 尚未还原的明确差异

- 普通卡片详情、个人信息表格编辑、主题列表/预览/切换本轮已补齐基础流程；普通卡热量与食物换算已补齐；运动专用页面和完整文案仍待补齐。详见 [记录内容、个人信息与主题](details-profile-themes.md)。
- 日历首次使用引导动画、未来待办，以及部分票卡角标尚未还原。当前长按菜单已支持查看卡片与编辑动态，目标/提醒入口已接通，详见 [自定义卡与提醒](custom-cards-reminders.md)。
- 备注已移回时间线/记录的动态编辑入口，支持单张照片与草稿；已有旧备注继续可读。
- 我的昵称、头像、性别已读取本地资料；原版账户/云同步流程仍未接入。
- 以上差异不能归结为“只差像素”；还需要继续实现，不应把当前版本当作最终 1:1 交付。

## 验证

- `.build/FidelityFinal.xcresult`：10 个业务测试与 4 条 UI 流程全部通过。覆盖本地新增/重启/删除、中英文与语言切换、周/月切换、滑动翻月、无数值卡补打、系统大字号启动。
- 按截图修复推荐大卡本地化键显示、键盘最后一行被压缩、我的顶部白条、日历容器覆盖子按钮可访问性标识。
- 151 条本地化通过脚本校验，资源清单全部文件与原版逐字节一致。
- 当前可审阅截图：`.build/ui-review/`。名称以 PunchCard 开头表示还原目标，截图内容实际是 KeepUp，**不是原版截图**。
