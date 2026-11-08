# 歌谱 · iPad 版（TrollStore / 巨魔商店）

纯原生 SwiftUI 工程，面向 iPad（iPadOS 15+），安装包内**不含任何歌谱图片**，全部素材来自你自己 NAS 的 WebDAV 目录。

## 这个文件夹是什么

```
01_App源码/
├── project.yml                     # XcodeGen 工程描述（不用手改 pbxproj）
├── Sources/
│   ├── Info.plist                  # 仅 iPad、允许局域网/明文 HTTP、允许文件共享
│   ├── GePuApp.swift               # 入口 + 四个 Tab
│   ├── Assets.xcassets/            # App 图标、强调色
│   ├── Core/                       # 数据 / 搜索 / WebDAV / 同步
│   └── Views/                      # 全部界面
├── Tools/make_icon.py              # 图标生成脚本（Pillow）
└── .github/workflows/build-ipa.yml # 云端一键出 IPA
```

## 怎么出 IPA（两条路，选一条）

### 路线 A：云端编译（不需要 Mac，推荐）

1. 把 **`01_App源码` 整个文件夹的内容**上传到一个 GitHub 仓库（根目录要能看到 `project.yml`）。
2. 打开仓库 → `Actions` → 左侧 `Build IPA` → 右侧 `Run workflow`。
3. 约 8~12 分钟跑完（首次装 XcodeGen 会慢一点），点进这次运行，页面底部 `Artifacts` 下载 `GePu-IPA`（一个 zip）。
4. 解压得到 `GePu.ipa`，用 AirDrop / 文件 App / 局域网传到 iPad，在 TrollStore 里点开安装。

> 公开仓库的 macOS 构建额度免费；私有仓库会消耗配额（macOS 按 10 倍计费）。

### 路线 B：有 Mac，本地编译

```bash
brew install xcodegen
cd 01_App源码
xcodegen generate
xcodebuild -project GePu.xcodeproj -scheme GePu -sdk iphoneos -configuration Release \
  -derivedDataPath build CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" build
mkdir -p Payload && cp -R build/Build/Products/Release-iphoneos/GePu.app Payload/
codesign --force --deep --sign - Payload/GePu.app
zip -qry GePu.ipa Payload
```

或者直接跑 `02_云端编译/build_local_mac.sh`。

## 工程要点

| 设计 | 实现 |
| --- | --- |
| 唯一标识 | 歌谱 id = 原图内容哈希（NAS 侧生成），改名/移动目录都不会变，App 全程按 id 存取 |
| 数据存储 | `Documents/data/*.json` + `Documents/thumbs/<id>.jpg` + `Documents/originals/<id>.<ext>` |
| 同步 | 手动触发；拉 `index.json` → `thumbs/` → `ocr.json`；推 `meta/<id>.json`；删原图/缩略图/OCR/元数据 |
| 搜索 | 歌名（繁简归一）+ 拼音首字母 + OCR 文本，三路匹配，带权重排序 |
| 看图 | `UICollectionView` 横向分页 + 每页 `UIScrollView` 缩放/双击放大/拖动 |
| 滑动范围 | 详情页接收 `scope`：首页=全库，搜索结果=结果集，标签页=该标签集合 |
| 删除 | 首页删除 → 回收站；回收站彻底删除 → 待同步队列 → 下次同步联动删 NAS |

编译环境要求：Xcode 15+（macos-14 runner 自带 Xcode 15/16），部署目标 iPadOS 15.0。
