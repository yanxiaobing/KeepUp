# 首页还原检查

2026-09-18。首页尚未完成原版 1:1 验收；以下修补不能代表整页完成。

## 本轮修补

- 卡片区横向滑动切换前一天／后一天，同步日期选中态、月份标题、回到今天按钮及补打／待办入口。纵向滚动继续浏览当前日期的卡片，切日重置滚动位置。
- 周／月切换增加过渡，遵循系统减弱动态效果设置。
- 待办日期使用虚线圈；有记录日期的选中外圈使用记录色，而非一律使用今天的颜色。
- 底部插画按记录、待办、固定卡及添加入口的总数判断是否显示；已归档卡不再进入固定待打卡列表。

依据：原工程 `Calendar/Controllers/XBCalendarCardListViewController.m`、`Calendar/Views/XBCalendarListCell.m`、`Calendar/Views/XBCalendarItemCell.m`。

## 已确认仍需还原

- 卡片区当前在手势结束时切日，尚无原版随手指移动的连续分页过渡。
- 首次使用的提示动画、完成周／月切换后的提示消隐。
- 卡片与长按已在后续轮次替换，详见 [卡片与长按还原](calendar-cards-restoration.md)。
- 计步／跑步／骑行专用卡；不同卡型的日期标记颜色优先级。
- 复杂混合卡片的完整排序验收；已恢复完成的起床卡优先与完成卡时间正序。
- 原版与 KeepUp 相同数据、日期、设备尺寸的逐状态截图对照。现有截图不能证明整页视觉验收通过。

## 验证范围

新增 `testHomeCardAreaChangesDayAndReturnsToToday`，覆盖卡片区切到明天、回到今天、切到昨天和前天、打开并关闭补打入口后保留日期。回归 `testCalendarScopeAndBackfill`，覆盖周／月切换、日历翻页和保存补打记录。

验证结果：上述两条 UI 测试在 iPhone 17 Pro / iOS 26.5 模拟器通过（0 失败）；结果包 `.build/HomeReview.xcresult`，截图位于 `.build/home-review-images/`。截图是 KeepUp 当前状态，并非原版对照图。
