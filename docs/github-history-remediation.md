# GitHub History Remediation

Deleting a file in a new commit does not remove it from existing Git history.
Anyone who can read old commits may still be able to recover the previous
content until history is rewritten, and even then existing clones, forks, pull
request refs, caches, or downloaded copies may still exist.

## First Decide the Severity

Low risk examples:

- Local usernames in Xcode user state paths.
- Apple Developer Team ID.
- Bundle identifiers.
- Non-secret project metadata.

These are usually worth cleaning up going forward, but they do not normally
require emergency history rewriting.

High risk examples:

- Private keys.
- Certificates or provisioning profiles.
- App Store Connect API keys.
- Passwords, tokens, session cookies, or personal access tokens.
- Private user data or clipboard content.

For high risk content, assume it is exposed.

## If a Real Secret Was Committed

1. Revoke or rotate the secret immediately.
2. Remove the file or value from the current working tree.
3. Rewrite Git history with a tool such as `git filter-repo` or BFG.
4. Force-push the cleaned branches and tags.
5. Ask collaborators to re-clone or carefully rebase from the cleaned history.
6. Check GitHub pull requests, forks, releases, Actions logs, and issue
   attachments for remaining copies.
7. Contact GitHub Support if sensitive data remains visible in GitHub-managed
   cached views after cleanup.

History rewriting reduces exposure in the canonical repository, but it cannot
guarantee that every copy on the internet disappears.

## If Only Project Metadata Was Committed

For metadata such as Team ID, bundle identifiers, or an Xcode user state path,
the practical fix is usually:

1. Stop committing that data going forward.
2. Add ignore rules and local config files.
3. Remove generated user state from the current tree.
4. Rewrite history only if the repository is very new or the metadata is
   personally unacceptable to keep in old commits.

## TypeCarrier Current Policy

TypeCarrier keeps personal signing configuration in
`Configs/Signing.local.xcconfig`, which is ignored by Git. Public defaults live
in `Configs/TypeCarrier.xcconfig` and use placeholder bundle identifiers.
