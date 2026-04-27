# v0 原型说明

## 当前状态

第一版原生 TypeCarrier 原型已经打通端到端流程：

- `TypeCarrieriOS` 提供 iPhone 文本输入和发送界面。
- `TypeCarrierMac` 作为菜单栏接收端运行，并带有 Debug Window。
- `TypeCarrierCore` 共享 payload、envelope、连接状态和 Multipeer 传输逻辑。

手动测试已确认核心工作流：

> iPhone 输入 -> 本地 Multipeer 发送 -> Mac 接收 -> 粘贴到当前光标。

## 本地开发

在仓库根目录生成 Xcode 工程：

```sh
xcodegen generate
```

用 Xcode 打开 `TypeCarrier.xcodeproj`。主要 scheme：

- `TypeCarrieriOS`
- `TypeCarrierMac`
- `TypeCarrierCore`

从命令行运行 Mac 菜单栏 app：

```sh
./script/build_and_run.sh
```

使用 `./script/build_and_run.sh --verify` 可以构建、启动并确认 app 进程存在。

## 首次手动测试路径

1. 在 Mac 上启动 `TypeCarrierMac`。
2. 打开菜单栏项，选择 `Request Accessibility`。
3. 在系统设置中为 Mac app 开启 Accessibility 权限。
4. 让 Mac 连接 iPhone 热点。
5. 在 iPhone 上运行 `TypeCarrieriOS`。
6. 把 Mac 光标放到一个文本输入框。
7. 在 iPhone 上输入或听写文本，然后点击 Send。

## v0 已知限制

- 自动连接第一个发现的 Mac peer。
- 还没有配对码或可信设备列表。
- 还没有重试队列。
- 剪贴板恢复只处理纯字符串内容。
- 还没有“只接收到剪贴板，不自动粘贴”模式。
