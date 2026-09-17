# 记录内容、个人信息与主题

本轮在 iOS 26.5 / iPhone 17 Pro 对照原版实现。业务页面继续复用 PunchCard 图片与布局，系统导航、菜单、分享和裁剪使用 iOS 26 原生样式。

## 已接通

- 日历记录点击：整页卡片详情；原版香蕉底纹、人物图、圆形背景、标题与鼓励文案。记录操作菜单提供编辑动态和删除，分享提供图片预览、保存相册及系统分享面板。
- 时间线：无已发布内容或有草稿时点击进入编辑；已发布内容点击进入详情。长按可查看卡片或编辑动态。发布后的文字与单张照片显示在记录下方。
- 动态编辑：原版 245 点白色编辑区域、文字、100 点缩放图片位、删除图片按钮和单图说明。照片选择后使用官方 TOCropViewController 3.2.0 正方形裁剪；再次点击照片可重新裁剪。
- 草稿：取消时可保留或放弃；保留草稿可在重启后继续。草稿与已发布内容分开，放弃本次编辑不删除已有内容。清空并保存可删除附加内容，打卡本身保留。
- 个人信息：头像入口及设置内的资料入口打开原版列表布局；头像、昵称、性别、出生年、身高、体重逐项保存。昵称结束输入后保存，身体资料使用标尺。修改体重同时添加一条体重记录，与资料在同一事务提交。
- 皮肤：原版 14 套列表、城市文案和预览，中文复用原版预览图，英文用同结构的本地化日历。未解锁主题转会员墙；已验证会员可选择主题。选择保存在本机，日历插画、日期选中色、底栏、时间线与详情底色随之更新。

## 存储

WCDB schema 3 新增 `entry_content` 表，按打卡 UUID 保存发布内容和草稿；旧打卡备注继续可读。保存发布内容时同步更新旧 `entries.note`，删除记录时在事务内删除对应内容。图片为 512×512 JPEG；文字限制 1000 字，图片限制 5 MB。

主题选择为本机显示偏好 `preference.themeID`；测试重置仅重置测试数据及测试所用偏好。

## 原版依据

- `Cards/CardDetails/Views/BCCardResultView.m`
- `Cards/CardDetails/Trends/PCCardTrendsViewController.m`
- `Me/MeInfoSetting/PCMeInfoSettingViewController.m`、`PCMeInfoSettingCell.m`
- `Skin/PCSkinListViewController.m`、`Skin/SkinDetail/PCSkinDetailsViewController.m`
- 只读提取 `Resource/database.db` 的 `CALENDAR_STYLE` 配置至 `Resources/themes.json`。

`.build/ReferenceUIHarness` 仅增加测试入口，原 PunchCard 工作区保持干净。原版截图为 `.build/ui-review/Reference-Entry-*`、`Reference-Profile-Personal.png`、`Reference-Themes.png`、`Reference-Theme-Preview.png`。

## 当前边界

- 全 App 尚未完成。自定义卡、固定卡、每周进度与提醒设置已在 [后续一轮](custom-cards-reminders.md) 实现；未来待办和体重已分别在[待办与起床卡](scheduled-cards-wake-up.md)、[体重记录与目标](weight-cards.md)实现，运动传感器与 GPS 仍待完成。
- 详情当前覆盖普通卡及本地体重记录的基础卡片展示；普通卡的热量/食物换算已补齐（见 [热量与食物换算](activity-energy.md)）；完整随机鼓励文案、专用运动详情和地图分享尚未补齐。分享底部使用 KeepUp 名称和记录日期，不复制原版 App 二维码。
- 个人资料和动态当前在开发阶段直接编辑；原版相关会员/广告解锁规则等待独立 JSON 与权益配置接入。主题会员验证代码已接通，但真实购买后解锁尚未进行沙盒交易验收。
- 相机需真机验收；相册保存和系统分享不会自动对外发布。
- 云同步、广告、远程 JSON 拉取仍按既有阶段安排推进。

## 验证记录（2026-09-16）

在 iOS 26.5 / iPhone 17 Pro 模拟器分批验证；下列为各组最终通过结果，不代表早期完整测试包全部通过。

| 范围 | 通过结果 | 结果包（`.build/`） |
| --- | --- | --- |
| WCDB、资料字段合并、体重事务、草稿/发布隔离、schema 2 升级等业务测试 | 15 个测试函数 | `DetailsAndProfileFirst.xcresult` 业务测试组 |
| 日历/补打卡、语言切换、重启及删除、大字体 | 4 条 UI 流程 | `DetailsAndProfileFirst.xcresult` 的 `KeepUpUITests` 组 |
| 中英文资料填写与会员墙、头像裁剪、关闭会员墙 | 4 条 UI 流程 | `DetailsProfileThemesSecond.xcresult` 的 `ProfileMembershipUITests` 组 |
| 个人信息修改并生成体重记录 | 1 条 UI 流程 | `DetailsProfileThemesSecond.xcresult` |
| 中文详情/编辑、照片发布/再次裁剪取消/草稿重启恢复/放弃修改 | 2 条 UI 流程 | `EntryContentFinal.xcresult` |
| 主题中文名称、英文预览、会员入口及取消 | 1 条 UI 流程 | `ThemesAndPhotoExportVerified.xcresult` 的主题测试 |
| 分享图片实际写入模拟器相册 | 1 条 UI 流程 | `PhotoExportFinal.xcresult` |

累计 15 个业务测试和 13 条不同 UI 流程通过。相册保存测试发现并修复了 Photos 后台回调继承 MainActor 导致的闪退；系统分享未选择外部收件人或实际发送。

本地化检查通过 266 条中英文条目；688 个资源文件逐一与 PunchCard 原文件及清单 SHA256 比对一致（295 个 imageset）。最新截图位于 `.build/ui-review/`。原 PunchCard 工作区未改动。
