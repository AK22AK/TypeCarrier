# TypeCarrier 想法

## 问题

在 Mac 上工作时，很多长文本其实更适合在手机上输入或语音转文字。手机离嘴更近，更容易拿起，也能使用用户已经习惯的移动输入法和语音输入能力。

现在常见的手动流程是：

1. 在 iPhone 上打开备忘录或任意文本输入框。
2. 用自己喜欢的输入方式输入，比如系统听写、第三方输入法或语音键盘。
3. 全选文本。
4. 复制。
5. 回到 Mac。
6. 粘贴到当前输入位置。

这里真正麻烦的不是语音识别，而是把手机上已经识别好的文本送到 Mac 当前光标位置。

## 核心想法

TypeCarrier 把 iPhone 变成 Mac 的临时文本输入面板。

用户打开 iPhone app，用任意已安装键盘输入或听写一段文字，然后点击发送。Mac app 收到文本后，把它插入到当前聚焦的输入位置。

## 产品定位

TypeCarrier 不是：

- 语音识别引擎。
- 剪贴板历史管理器。
- 通用文件传输工具。
- 完整的远程键盘或鼠标控制器。
- 云同步平台。

TypeCarrier 是：

- 从 iPhone 到 Mac 的专注文本传送工具。
- 对“复制到手机剪贴板，再回 Mac 粘贴”的一步替代。
- 一个 local-first 的小工具，把手机输入的文字送进 Mac 光标。

## 命名

当前工作名是 `TypeCarrier`。

这个名字表达的是“承载 typed/dictated words 的小工具”。它比 `PasteToMac` 或 `Clipboard Sync` 更不局限，同时仍然指向输入和传递。

可能的 tagline：

> Carry words from your iPhone to your Mac cursor.
