# 竞品分析

## 总结

TypeCarrier 主要应和跨设备文本/剪贴板工具比较，而不是和语音识别工具比较。

核心差异是：

> 竞品通常同步、保存或转移文本；TypeCarrier 要把文本直接插入 Mac 当前光标。

## Apple Universal Clipboard

Apple 的通用剪贴板已经支持在 iPhone 上复制、在 Mac 上粘贴。

优势：

- 系统内置。
- 不需要额外 app。
- 支持多种数据类型。

相对 TypeCarrier 的弱点：

- 用户仍然要在 iPhone 上选择并复制。
- 用户仍然要回到 Mac 手动粘贴。
- 同步时机有时不够可感知。
- 它是系统剪贴板能力，不是专注的文本输入工作流。

TypeCarrier 应通过去掉“手机复制”和“Mac 粘贴”两个动作来胜出。

## ClipSync / Macty

ClipSync 是 Apple 生态中比较接近的竞品。它是 Macty 的 iOS 伴侣，Macty 是一个 macOS 菜单栏工具箱。其公开定位主要是通过二维码配对、本地 Wi-Fi 或蓝牙，在 Mac 和 iPhone 之间发送和接收剪贴板文本，不需要账号或互联网。

相似点：

- iPhone 和 Mac 配对。
- 文本在设备间传输。
- 可以 local-first。
- 不需要账号是自然选择。

差异：

- ClipSync 更像剪贴板分享/同步。
- TypeCarrier 应定位为“手机到 Mac 的文本输入”。
- TypeCarrier 的关键结果是自动插入 Mac 当前光标。
- TypeCarrier 的 iPhone UI 应为草稿输入和听写优化，而不是浏览剪贴板历史。

策略含义：

如果 TypeCarrier 只是把文本发到 Mac 剪贴板，差异化会很弱。MVP 必须优先做好自动粘贴到当前输入焦点。

## 剪贴板管理器

例子：Paste、PasteNow、CloudClip。

这类工具关注剪贴板历史、组织、搜索和跨设备复用。

优势：

- 剪贴板工作流成熟。
- 有历史和搜索。
- 使用范围不局限于 iPhone 到 Mac。

相对 TypeCarrier 的弱点：

- 不为“手机输入后立刻进入 Mac 光标”优化。
- 通常从已复制内容开始，而不是一个主动输入界面。
- 用户可能仍要选择条目并手动粘贴。

TypeCarrier 不应在剪贴板历史上竞争。

## LocalSend / AirDroid / KDE Connect

这些是通用传输或设备连接工具。

优势：

- 跨平台支持。
- 能发送文本和文件。
- 覆盖很多设备工作流。

相对 TypeCarrier 的弱点：

- 功能范围比 TypeCarrier 宽得多。
- 文本通常落在接收 app、通知或剪贴板里。
- 它们不是围绕“插入当前 Mac 光标”这个主动作设计的。

TypeCarrier 应保持更窄、更快。

## 给自己发消息的工作流

例子：微信文件传输助手、iMessage 发给自己、Telegram Saved Messages、Slack 私信自己。

优势：

- 用户已经安装。
- 互联网传输可靠。
- 使用习惯成熟。

相对 TypeCarrier 的弱点：

- 文本落在聊天 app，而不是目标 Mac 输入框。
- 用户还要再次复制粘贴。
- 隐私和数据驻留取决于聊天服务。
- 会打断当前 Mac 上下文。

TypeCarrier 应通过避免上下文切换取胜。
