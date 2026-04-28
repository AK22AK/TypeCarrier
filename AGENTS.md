# Agent Instructions

These instructions apply to the entire repository.

## Commit And PR Messages

Use English for commit messages and pull request titles/bodies.

Commit and PR titles must use this format:

```text
[type] Short imperative summary
```

Use lowercase type names such as `fix`, `feat`, `dfx`, `docs`, `test`, `refactor`, or `chore`.

Commit and PR bodies must follow the established project style:

```text
One concise summary paragraph describing the overall change and why it exists.

- Area: Specific change or behavior, written as a complete phrase

- Area: Another specific change or behavior

- Area: Tests, validation, or user impact when relevant
```

Do not add literal section labels such as `Summary`, `Details`, `Total`, `总`, or `分` unless the user explicitly requests them.

Before committing or opening/updating a PR, inspect recent history with `git log --format=fuller -1` and match the message structure used by the latest merged project changes.
