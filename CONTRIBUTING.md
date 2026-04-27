# 贡献指南

TypeCarrier 仍处在早期原型阶段。小而聚焦的改动比大范围重写更容易评审和合并。

## 工作流

功能开发、行为变更、发布配置、权限、传输逻辑和自动粘贴相关改动，建议走 Pull Request。请保持 `master` 可构建。

维护者可以直接提交小的文档修正。

打开 Pull Request 前：

- 运行 `xcodegen generate`。
- 运行 core tests。
- 如果改动涉及 app 代码，构建 iOS 和 macOS target。
- 不要提交个人签名文件、Xcode 用户状态、证书或 provisioning profile。

公开贡献默认按 Apache License 2.0 提交。
