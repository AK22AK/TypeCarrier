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

## Commit and PR messages

Use English for commit messages and pull request titles/bodies.

Titles should use `[type] Short imperative summary`, for example:

```text
[fix] Repair connection state transitions
[dfx] Enhance connection diagnostics
```

Bodies should start with one concise summary paragraph, followed by blank-line-separated bullets in the established project style:

```text
Clarify the overall change and why it exists.

- Area: Describe one focused part of the change

- Area: Describe another focused part of the change

- Tests: Describe validation or regression coverage when relevant
```

Do not add literal section labels such as `Summary`, `Details`, `Total`, `总`, or `分` unless they are explicitly requested.

公开贡献默认按 Apache License 2.0 提交。
