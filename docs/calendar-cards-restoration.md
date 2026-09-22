# 首页卡片与长按操作还原

2026-09-18。本轮聚焦已接入的普通、自定义、体重、起床、固定待打、计划待办卡及添加入口；计步、跑步、骑行的专用卡仍随对应功能待实现。

## 卡片

直接对照 PunchCard 的 `XBCalendarCell`、`XBCalendarNormalCell`、`XBCalendarCustomCell`、`XBCalendarWeightCell`、`XBCalendarEaryCell`、`XBCalendarResultView`、`XBCalendarProgressView`：

- 88 × 116 点随屏宽缩放；74 × 87 点插画，按原版中心偏移量摆放。
- 数值从错误的底部描边框移回左上角飘带，18 点高度、12 点 HelveticaNeue-Light、原版尾部与高光图片。
- 普通卡 `5fc6dc`、体重 `f5d039`、起床 `5fdcc9`、待打 `babdc2`。体重保留一位小数。
- 统一固定卡与待办卡的票面，恢复待打插画、提醒图标和对应卡型的周进度色。起床待打不显示普通卡的“待打”飘带。
- 未来添加入口使用 25 点加号，补打入口使用 45 点图；保留原版三边虚线、18 点底色条和票面遮罩。
- 完成卡按时间正序，完成的起床卡优先。

## 长按

移除首页卡片的系统 contextMenu。按 `XBCalendarCardLongPressMenuControl` 实现：

- 长按 0.5 秒；全窗口 Light 模糊与浅色覆盖；卡片快照留在原位置。
- 使用原版删除／打卡／提醒图片，54 点按钮、120 点半径、30° 间隔；左、中、右列采用对应扇形方向，右列反转按钮顺序。
- 0.25 秒展开、0.15 秒关闭；减弱动态效果时关闭动画。点空白关闭，松开长按不会同时触发卡片点击。
- 删除确认使用原版居中白色圆角框、文字与分隔线、左侧取消和右侧黄色删除按钮。
- 完成卡删除当前记录；待办卡删除该条计划；固定卡移除固定、提醒和周进度设置，保留历史记录。
- 打卡记录到今天，不把历史／未来页面的日期误传给打卡表单。完成的起床卡不显示重复打卡入口；归档自定义卡只允许删除；添加入口不提供长按菜单。
- 提醒打开对应卡的设置。查看卡片仍通过短按，编辑动态保留在详情页操作菜单里。原版回顾按钮在源码中被注释，本轮不添加。
- 保留读屏标签、按钮语义、卡片操作的辅助功能入口及 Escape 关闭。

## 参考渲染

在 `.build/ReferenceUIHarness` 的只读来源副本中增加独立启动参数，直接实例化原版 `XBCalendarNormalCell` 和长按菜单，以三张 10/20/30 分钟卡验证。仅修改副本的入口，未修改原工程或卡片实现。

- `.build/ui-review/Reference-Calendar-Cards.png`：原版卡片。
- `.build/ui-review/Reference-Calendar-Menu.png`：原版菜单。
- 参考图是独立卡片容器，不是原版整个首页；可用于检查卡片和按钮几何，不能证明首页背景已对齐。

补入的 6 组图片保持原 PNG 字节，校验和已加入 `punchcard-resource-manifest.json`。

## 验证结果

- `.build/CardRestorationFinal.xcresult`：6 条 UI 测试通过，0 失败。覆盖三列菜单、关闭菜单、提醒、重复打卡、删除确认／取消、记录删除和重启、固定卡删除、未来待办删除及打卡日期隔离、起床卡按钮规则、日历周／月切换、补打、卡片区切日。
- `.build/CardRestoration.xcresult`：自定义卡创建／重启、体重卡中文和英文流程这 3 条回归通过。首轮新菜单测试发现删除确认框的 UIKit 可访问性容器错误，已修复并在最终结果包全部通过。
- 人工检查了普通三列卡片、左右列长按菜单、体重卡、删除确认截图；与独立运行的原版普通卡及菜单核对了飘带、插画、标题条和按钮位置。
- `validate_configuration.py` 通过；753 个资源文件 SHA-256 全部与清单一致；`git diff --check` 通过。
- 全量 `validate_localization.py` 仍报告 14 个基线中已有的未翻译条目（与修改前 HEAD 对照一致），本轮新增 4 条文案均有中英文翻译，没有新增缺失项。校验器现同时识别 UIKit 的 accessibilityIdentifier 赋值，避免把自动化标识误认成文案。

可审阅截图在 `.build/ui-review/`：`KeepUp-Cards-Three-Columns.png`、`KeepUp-Card-Menu-Column-0.png`、`KeepUp-Card-Menu-Column-2.png`、`KeepUp-Card-Delete-Confirmation.png`、`KeepUp-Weight-Calendar-zh-Hans.png`。

## 卡片滚动与日历联动初版（2026-09-21，已由下方连续过渡替代）

- 卡片区上滑超过 30 点收起为所选日期所在周；下拉超过 30 点且列表已到顶部时展开整月。长列表中途下拉保持周视图，少量卡片和空白区同样支持手势。
- 每次拖动最多切换一次周／月视图，沿用原有动画及减弱动态效果设置；保留左右切日和日历自身的手势、切换按钮。辅助功能大字号下保留日期选择器。
- `.build/CalendarScrollLinkFinal.xcresult`：新增 2 条 UI 测试通过，覆盖少量卡片、未来空白区、左右切日、45 条记录长列表中途下拉及到顶展开。
- `.build/CalendarScrollLink.xcresult`：原有周／月按钮、月份翻页及补打回归通过；首轮新增测试因周／月布局的辅助功能元素类型变化而定位失败，调整测试查询后在上述最终结果包通过。
- 截图导出至 `.build/ui-review/calendar-scroll/`；`git diff --check` 通过。


## 连续拖动修正（2026-09-21）

初版仅在超过阈值时切换周／月网格，最终状态测试不能证明拖动手感。现保留完整月网格，按拖动距离连续调整裁切高度与所选周的纵向位置，松手按预计落点吸附；短距离慢拖回到原状态。月视图下优先由日历消耗上滑，周视图下保持卡片原生滚动，到顶下拉再展开；抵消列表顶部回弹产生的额外卡片位移。

- 移除可见的上下滑提示文字，保留箭头按钮和读屏标签。
- 收起时隐藏不可见日期的辅助功能元素，并将点击范围限制在可见日历内，避免隐藏日期挡住“今天”按钮。
- `.build/CalendarContinuousFinal.xcresult`：少量卡片／空白区、长列表到顶、原有日历翻页和补打这 3 条测试通过。慢拖测试的收放、短拖回弹、日期选中和可点击断言通过，末尾检查误用了普通记录关闭按钮标识，改为体重页标识后单独重跑。
- 慢拖过程实截 `.build/ui-review/calendar-mid-drag.png` 确认存在周／月之间的连续中间布局，卡片紧跟日历下缘；未据此宣称真机帧率或手感已验收。
- `.build/CalendarContinuousSlow.xcresult`：慢拖测试最终通过，包含短拖回弹、完整展开／收起、所选日期保持可点击及收起后打开体重卡；上述 4 条针对性 UI 检查均通过。`git diff --check` 通过。
