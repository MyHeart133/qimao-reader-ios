# 七猫阅读器 · iOS 自建客户端(QimaoReader)

自研的七猫内容 iOS 客户端 —— 界面与阅读器高度仿照七猫 App。
搜索 / 详情 / 目录 / 沉浸阅读 / 下载全本(TXT+EPUB)→ 文件 App 可见。

- 主色:七猫橙红 `#FF5B29`
- 阅读器:点击左/右边缘翻章,点击中间呼出菜单(进度滑条 / 目录 / 字号 / 四种背景主题:羊皮纸·白·护眼·夜间)
- 书架:阅读过/下载过的书自动入架,带进度「继续阅读」
- 下载:全本下载 TXT + EPUB(带封面),存放于 App 沙盒,可在「文件」App 中直接用「图书」打开

## 如何产出 IPA(无需 Mac)

本项目通过 GitHub Actions 在云端 macOS 构建机编译:

1. 把本项目上传到 GitHub(新建仓库,把全部文件推上去;或上传 `src.zip` + `.github/workflows/build.yml`)
2. 打开仓库的 **Actions** 页 → 运行 **Build Unsigned IPA**(push 后自动触发)
3. 等待约 3~6 分钟,构建完成
4. 在构建记录页底部 **Artifacts** 下载 `QimaoReader-unsigned-ipa`(zip)
5. 解压得到 `QimaoReader-unsigned.ipa` → 用**全能签**签名 → 安装到 iPhone

## 工作流说明

`.github/workflows/build.yml`:
- `macos-latest` 运行器 + `xcodegen` 生成 Xcode 工程
- `xcodebuild` 以 `CODE_SIGNING_ALLOWED=NO` 构建未签名包
- 打包 `Payload/` 为 IPA 并上传为构建产物

## 目录结构

```
.
├── .github/workflows/build.yml   # 云端构建流水线
├── project.yml                   # xcodegen 工程定义
├── QimaoReader/
│   ├── QimaoReaderApp.swift      # 入口 + TabView
│   ├── Theme.swift               # 七猫风主题(含阅读器四主题)
│   ├── QimaoAPI.swift            # 签名 / 接口 / AES-128-CBC 解密
│   ├── ZipWriter.swift           # 最小 ZIP(STORE)写入器
│   ├── Exporter.swift            # TXT / EPUB 导出
│   ├── ShelfStore.swift          # 书架 + 下载管理
│   ├── Components.swift          # 通用组件
│   ├── SearchView.swift          # 搜索页
│   ├── DetailView.swift          # 书籍详情页
│   ├── ReaderView.swift          # 阅读器(仿七猫)
│   ├── LibraryView.swift         # 书架页
│   └── Assets.xcassets/…         # App 图标
└── README.md
```

## 常见问题

- **构建失败**:打开失败日志,把错误贴给开发者即可;常见原因是 Xcode 版本对个别 API 的兼容,修一行就好
- **签名失败**:全能签选「完整签名」;首次安装需信任证书
- **打不开手上的书**:书籍数据来自公开网络接口,网络波动时重试即可
- **导出文件在哪里**:iPhone「文件」App → 我的 iPhone → 七猫阅读器 → qimao
