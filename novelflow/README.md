# NovelFlow

安静、耐用的 iOS 小说阅读器(SwiftUI + SwiftData,最低 iOS 17)。
本目录为 app 源码,通过仓库根目录的 GitHub Actions 工作流 `NovelFlow CI` 云端构建与测试。

## 书源(P7:聚合书源)

| 来源 | 搜索 | 详情 | 目录 | 正文 | 整本缓存 | 说明 |
|---|---|---|---|---|---|---|
| 七猫免费小说 | ✅ | ✅ | ✅ | ✅ | ✅ | 公开接口 + 参数签名 + AES-128-CBC 正文解密 |
| 起点中文网 | ✅ | ✅ | ✅ | 免费章 | ✅(至 VIP 界) | m.qidian.com 移动页;VIP 章节不破解,如实截断 |
| 番茄小说 | — | ✅ | ✅ | ✅ | ✅ | 热榜浏览 / 链接直达;正文 PUA 混淆由内置字表还原 |
| 202小说网 | ✅ | ✅ | ✅ | ✅ | ✅ | 聚合镜像(202 模板);目录分页自动翻页 |
| 非凡中文 | ✅ | ✅ | ✅ | ✅ | ✅ | 聚合镜像(202 模板,独立书库) |
| 新笔趣阁 | ✅ | ✅ | ✅ | ✅ | ✅ | 聚合镜像(202 模板,独立书库) |
| 飘天文学 | ✅ | ✅ | ✅ | ✅ | ✅ | 老牌站;GBK 编码(搜索参数按 GB18030 转义) |
| 笔趣阁(365) | ✅ | ✅ | ✅ | ✅ | ✅ | 独立书库,`/chapter/` 直链 |
| Gutenberg | ✅ | ✅ | — | — | 直链下载 | 公版书库(含 400+ 中文经典) |
| Open Library | ✅ | ✅ | — | — | — | 全球书目(发现型) |
| Webnovel(阅文官方) | ✅ | ✅ | — | — | — | 官方英译版(发现型) |

> 冷门书 / 老书 / 下架书(如《蛊真人》)通过聚合镜像站可以搜到并缓存全本;
> 起点 VIP 章节本身不做破解 —— 对应全本一般能在聚合镜像中找到。

## 使用入口

- **书库页搜索**:多源并发检索、**流式返回**(先到先显示,单源超时 12 秒自动跳过);结果标注来源;点卡片进详情。
- **在线阅读**:详情页「开始阅读(在线)」——拉一次目录即可开读,章节按需抓取、边读边缓存(相邻章预取);书架带「在线」角标,重开续读。
- **缓存全本**:逐章抓取 → 分章落盘(断点续传)→ 组装全文 → 升级为离线书(与在线书架共用同一条目)。
- **换源**:书籍详情 → 「换源 · 在其它书源中查找本书」,按书名跨源匹配(同作者优先)。
- **排版**:全部在阅读器内实时调 —— 字号 / 字体(苹方·宋体·楷体·系统)/ 行距 / 段距 / 首行缩进 / 页边距 / 预设(紧凑·默认·宽松)/ 主题 / 阅读模式 / 点按分区(改动防抖重排,阅读位置保持)。
- **番茄热榜 / 链接直达**:书库页「看番茄热榜」「链接打开…」(支持 fanqienovel.com / m.qidian.com 链接与裸 ID)。

## 架构速览

```
novelflow/NovelFlow/
├── Sources/
│   ├── ContentSource.swift       # 统一书源协议 + 能力声明
│   ├── SourceRegistry.swift      # 注册表 + 流式并发聚合搜索(单源超时)
│   ├── QimaoSource.swift         # 七猫(签名 + AES 正文解密)
│   ├── FanqieSource.swift        # 番茄(热榜/详情/目录/正文)
│   ├── QidianSource.swift        # 起点(搜索/详情/目录/免费章)
│   ├── Template202Source.swift   # 202 模板聚合镜像(202xs/非凡中文/新笔趣阁)
│   ├── PiaotiaSource.swift       # 飘天文学(GBK)
│   ├── Biquge365Source.swift     # 笔趣阁(365 模板)
│   ├── FanqieFontMap.swift       # 番茄 PUA 反混淆字表(362 项)
│   ├── OnlineChapterStore.swift  # 在线书:目录 + 边读边缓存的章节文件
│   ├── ChapterCacheManager.swift # 整本缓存管线(断点续传/组装/升级为离线书)
│   └── WebSourceSupport.swift    # HTTP/SSR 状态提取/HTML 清理/正则/编码工具
├── Reader/                       # 分页引擎 / 滚动阅读 / 书签 / 全文搜索 / 书内排版面板
├── Downloads/                    # 直链文件下载(断点续传)
└── Shelf/                        # 书架(在线角标) / 书库(流式搜索) / 详情 / 换源
```

## 维护备忘

- **番茄字表**:`FanqieFontMap` 由「当前字体 cmap × 思源黑体 SourceHanSansSC-Normal v2.002
  GID→字符」逐字形比对生成。若番茄更换字体(阅读页里 `awesome-font/c/<hash>` 变化),
  未覆盖的 PUA 字符会原样保留(少量缺字),需重新生成字表。
- **七猫签名/AES**:常量集中在 `QimaoSource` 顶部;正文解密为 AES-128-CBC,
  密钥为 16 位 ASCII 口令,IV 为每条密文前 16 字节。
- **起点 VIP**:章节页 `<main class="... lock-mask">` 即锁定,缓存时在此截断并注明。
- **测试**:`NovelFlowTests/WebSourceTests.swift` 覆盖签名向量、AES 样本、字表还原、
  三类来源的页面解析与锁定检测(全部离线,不依赖网络)。

## 构建

推送到 GitHub 后由 Actions 自动构建:

1. `xcodegen generate`(工程由 `project.yml` 生成)
2. `xcodebuild ... test`(模拟器)
3. Release 未签名 IPA → 构建产物 `novelflow-unsigned-ipa`
