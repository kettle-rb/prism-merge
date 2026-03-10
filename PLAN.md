# PLAN.md

## Goal
Adopt the shared Comment AST & Merge capability in `prism-merge` while preserving Ruby-specific comment behavior such as magic comments, shebang handling, and native Prism comment ownership.

`psych-merge` is the reference for shared capability shape, but `prism-merge` should remain the strongest native-comment implementation in the family.

## Current Status
- `prism-merge` is already comment-aware and should be treated as a native-comment integration target, not a blank slate.
- The gem has the standard merge-gem layout plus deeper Ruby-specific integration needs.
- Ruby comments matter semantically for style, file headers, magic comments, and code readability.
- The plan here is less about inventing comment handling and more about normalizing it around the shared `ast-merge` comment API.

## Integration Strategy
- Wrap Prism-native comment ownership in shared comment regions / attachments.
- Preserve Ruby-specific comment classes or behavior where needed, especially for magic comments.
- Expose shared capability methods consistently with other merge gems.
- Use shared comment fallback rules for matched nodes, removed nodes, and document boundaries.
- Keep native precision wherever Prism already provides better ownership than source-only heuristics.

## First Slices
1. Expose `comment_capability`, `comment_augmenter`, and normalized attachments from file analysis.
2. Align document prelude/postlude handling with the shared `psych-merge` model.
3. Preserve destination comments when matched Ruby nodes are emitted from template-preferred content.
4. Preserve or promote comments for removed destination-only Ruby nodes where removal is enabled.
5. Revisit magic comment, shebang, and freeze-node interactions after the shared layer is stable.

## First Files To Inspect
- `lib/prism/merge/file_analysis.rb`
- `lib/prism/merge/node_wrapper.rb`
- `lib/prism/merge/smart_merger.rb`
- `lib/prism/merge/comment.rb`
- any Ruby-specific comment classes under `lib/prism/merge/comment/`

## Tests To Add First
- file analysis specs for shared capability exposure
- smart merger specs for matched-node destination comment fallback
- magic comment specs
- freeze / deduplication / recursive body merge comment regressions
- reproducible fixtures for comment-heavy Ruby files if not already present

## Risks
- Magic comments are Ruby-specific and cannot be treated as generic comments.
- Comment ownership around `end` and nested bodies can drift if normalized too aggressively.
- Native Prism ownership and shared ownership must not conflict.
- Shebang and file-header handling must remain exact.

## Success Criteria
- Shared comment capability is exposed consistently without losing Ruby-specific behavior.
- Matched and removed Ruby nodes preserve comments correctly.
- Document headers, shebangs, and magic comments remain stable.
- Recursive body merges keep comment association intact.
- The gem remains the strongest native-comment example in the family.

## Rollout Phase
- Phase 1 target.
- Recommended after `jsonc-merge` and `dotenv-merge` so the shared API is battle-tested before normalizing native Prism ownership.

## Progress
- 2026-03-09: Phase 1 / Slice 1 completed.
- Added shared comment capability exposure over Prism-native ownership in `lib/prism/merge/file_analysis.rb`.
- Exposed `comment_capability`, `comment_nodes`, `comment_node_at`, `comment_region_for_range`, `comment_attachment_for`, and `comment_augmenter` using native Prism comment ownership rather than source-only inference.
- Added a lightweight native augmenter that preserves Prism-owned leading/in-line attachments plus document prelude/postlude behavior.
- Preserved Ruby-specific `Prism::Merge::Comment::*` nodes while surfacing them through the shared API.
- Added focused file-analysis regressions for native capability exposure, native attachments, postlude handling, and comment-only file preamble behavior.
- Revalidated focused Prism comment/file-analysis/magic-comment specs and the full `prism-merge` suite.
- 2026-03-09: Slice 2 completed.
- Preserved destination-owned leading, inline, and trailing comments for matched template-preferred atomic Ruby nodes.
- Preserved blank-line spacing around fallback comment regions and prevented duplicate inter-node gap emission after preserved destination trailing comments.
- Added exact-output smart-merger regressions for leading+inline fallback, trailing fallback, and trailing-gap deduplication.
- 2026-03-09: Slice 3 header hardening started.
- Aligned comment-only destination header prelude handling with the Ruby code path by preserving destination shebang and magic-comment prefix lines before generic comment-only merging.
- Deduplicated destination magic-comment header lines by type in comment-only merges while suppressing already-emitted header lines from later node emission.
- Tightened magic-comment regressions to exact header-order expectations and added a shebang-plus-magic comment-only regression.
- Revalidated focused `smart_merger_spec`, focused `smart_merger_magic_comment_spec`, and the full workspace-backed `prism-merge` suite.
- 2026-03-09: Slice 3 freeze-semantics follow-up completed.
- Aligned `SmartMerger#frozen_node?` with `FileAnalysis#frozen_node?` so only directly owned leading freeze markers freeze a node; nested markers remain container-content metadata rather than freezing the outer container.
- Added direct and integration regressions proving nested frozen children still preserve destination content without stealing outer container comments under template preference.
- Revalidated freeze-focused specs, focused smart-merger specs, and the full workspace-backed `prism-merge` suite.
- 2026-03-09: Slice 3 recursive-wrapper trailing comment stability completed.
- Taught `merge_node_body_recursively` to preserve external trailing comments after recursively merged wrapper nodes, mirroring the atomic-node path.
- Added exact-output regressions for destination trailing-comment fallback and template trailing-comment retention on recursively merged containers.
- Revalidated focused smart-merger specs and the full workspace-backed `prism-merge` suite.
- 2026-03-09: Slice 3 recursive-wrapper inline-comment stability completed.
- Taught `merge_node_body_recursively` to preserve destination inline comments on recursive wrapper opening lines by supplementing native owner attachments with Prism parse-result comments on the wrapper boundary lines.
- Added exact-output regressions for template-preferred recursive class wrappers and `Gem::Specification.new do ... end` block wrappers, covering both opening-line and closing-line inline comment fallback.
- Revalidated focused smart-merger specs and the full workspace-backed `prism-merge` suite.
- 2026-03-09: Slice 3 recursive BeginNode clause preservation completed.
- Fixed `merge_node_body_recursively` / `extract_node_body` so matched `begin ... rescue ... ensure ... end` wrappers no longer collapse to `begin ... end` during recursive merging; clause tails now remain intact while the main body still merges recursively.
- Added an exact-output regression proving template-preferred recursive begin wrappers preserve destination opening/end inline comments, template rescue/ensure clauses, and destination-only body content.
- Revalidated focused smart-merger specs and the full workspace-backed `prism-merge` suite.
- 2026-03-09: Slice 3 recursive BeginNode clause-header inline fallback completed.
- Fixed recursive `begin ... rescue ... ensure ... end` emission so destination inline comments on `rescue` / `else` / `ensure` headers are preserved under template preference by mapping corresponding clause headers across template and destination rather than relying on raw line numbers.
- Added an exact-output regression proving recursive begin wrappers preserve destination clause-header inline comments even when destination-only body lines shift clause line numbers.
- Revalidated focused smart-merger specs and the full workspace-backed `prism-merge` suite.
- 2026-03-09: Slice 3 recursive BeginNode destination-tail fallback completed.
- Fixed template-preferred recursive `begin` merging so destination `rescue` / `else` / `ensure` tails are preserved when the template wrapper has no clause tail at all, instead of collapsing back to `begin ... end`.
- Added an exact-output regression proving recursive begin wrappers keep destination clause tails, clause-header inline comments, and destination-only body content when the template provides only the main body.
- Revalidated focused smart-merger specs and the full workspace-backed `prism-merge` suite.
- 2026-03-09: Slice 3 recursive BeginNode mixed-tail clause merging completed.
- Fixed recursive `begin` tail emission to assemble `rescue` / `else` / `ensure` clauses clause-by-clause instead of selecting a single whole-tail source, so template-preferred shared clauses can coexist with later destination-only clauses like `ensure`.
- Added an exact-output regression proving template-preferred recursive begin wrappers preserve destination-only later clauses instead of dropping cleanup logic when the template has only an earlier clause.
- Revalidated focused smart-merger specs and the full workspace-backed `prism-merge` suite.
- 2026-03-09: Slice 3 recursive BeginNode multi-rescue preservation completed.
- Fixed recursive `begin` clause emission so chained `rescue` branches are represented and merged per branch rather than as a single rescue bucket, preserving later destination-only rescue handlers under template preference.
- Switched rescue-chain traversal to Prism's non-deprecated `subsequent` API when available to avoid forward-compatibility warnings while retaining support for older Prism behavior.
- Added an exact-output regression proving template-preferred recursive begin wrappers preserve later destination-only `rescue` branches instead of dropping specialized recovery logic.
- Revalidated focused smart-merger specs and the full workspace-backed `prism-merge` suite.
- 2026-03-09: Slice 3 recursive BeginNode rescue-signature matching completed.
- Fixed recursive `begin` rescue alignment so shared rescue branches are matched by exception signature (with occurrence counts for repeated signatures) instead of raw branch index, preserving destination-inserted earlier rescue branches without duplicating shared handlers.
- Added an exact-output regression proving template-preferred recursive begin wrappers preserve an inserted destination `rescue IOError` branch that appears before a shared `rescue StandardError` branch.
- Revalidated focused smart-merger specs and the full workspace-backed `prism-merge` suite.
- 2026-03-09: Slice 3 recursive BeginNode shared-clause body merging completed.
- Fixed recursive `begin` handling so shared `rescue` / `else` / `ensure` clauses can recursively merge structurally matching body statements, preserving destination-only additions inside a shared clause without regressing whole-clause preference when no structural match exists.
- Added an exact-output regression proving template-preferred recursive begin wrappers keep template-owned shared clause statements while preserving destination-only extra statements inside matching `rescue` and `ensure` bodies.
- Revalidated focused smart-merger specs and the full workspace-backed `prism-merge` suite.
- 2026-03-09: Slice 3 recursive BeginNode shared-clause leading-comment preservation completed.
- Fixed shared clause-body extraction so recursive `rescue` / `else` / `ensure` body merges preserve leading comments and blank lines between the clause header and the first statement instead of dropping them before nested merging begins.
- Added an exact-output regression proving template-preferred shared `rescue` and `ensure` clause-body merges keep template-owned leading docs while preserving destination-only extra statements inside the same clause bodies.
- Revalidated focused smart-merger specs and the full workspace-backed `prism-merge` suite.
- 2026-03-09: Slice 3 recursive BeginNode shared-clause footer preservation completed.
- Fixed shared clause-body recursion so footer comments and blank-line suffixes after the last statement remain at the end of a recursively merged `rescue` / `else` / `ensure` body instead of being dropped, duplicated, or reordered ahead of destination-only statements.
- Added an exact-output regression proving template-preferred shared `ensure` clause-body merges preserve a shared footer comment after destination-only extra statements.
- Revalidated focused smart-merger specs and the full workspace-backed `prism-merge` suite.
- 2026-03-09: Slice 3 recursive BeginNode bare-rescue canonicalization completed.
- Fixed rescue-clause identity matching so bare `rescue` and explicit `rescue StandardError` are treated as the same logical clause, preventing duplicate overlapping rescue branches during recursive begin merging.
- Added an exact-output regression proving template-preferred recursive begin wrappers merge a bare `rescue` and an explicit `rescue StandardError => e` into one shared clause while preserving destination-only additions inside the rescue body.
- Revalidated focused smart-merger specs and the full workspace-backed `prism-merge` suite.
- 2026-03-09: Slice 3 recursive BeginNode shared-clause fallback comment preservation completed.
- Fixed the non-recursive shared-clause fallback path so template-preferred recursive begin merges still preserve an opposite-side leading comment block for a shared `rescue` / `else` / `ensure` body when clause-body recursion is intentionally skipped due to no structural matches.
- Added an exact-output regression proving a shared rescue clause keeps destination-owned leading docs while still using the template-preferred clause body content.
- Revalidated focused smart-merger specs and the full workspace-backed `prism-merge` suite.
- 2026-03-09: Slice 3 recursive BeginNode shared-clause fallback footer preservation completed.
- Fixed the shared-clause fallback path so opposite-side trailing footer suffixes after the last statement are preserved when clause-body recursion is skipped, preventing destination-owned footer comments from being silently dropped.
- Added an exact-output regression proving a shared `ensure` clause keeps a destination-owned footer comment after template-preferred body content when the clause body cannot recurse structurally.
- Revalidated focused smart-merger specs and the full workspace-backed `prism-merge` suite.
- 2026-03-09: Slice 3 recursive BeginNode freeze-aware clause fallback completed.
- Fixed shared-clause fallback so opposite-side freeze-marker wrappers are treated as semantic preservation boundaries rather than harmless docs; a freeze-marked destination clause body now remains atomic instead of wrapping template-preferred content with destination freeze markers.
- Added an exact-output regression proving template-preferred recursive begin merges preserve a freeze-marked destination rescue body atomically during shared-clause fallback.
- Revalidated focused smart-merger specs and the full workspace-backed `prism-merge` suite.
- 2026-03-09: Slice 3 recursive BeginNode rescue-exception order canonicalization completed.
- Fixed rescue-clause identity matching so equivalent exception lists are treated as order-insensitive sets, preventing duplicate semantically identical rescue branches when template and destination list the same exceptions in different lexical orders.
- Added an exact-output regression proving template-preferred recursive begin wrappers merge `rescue IOError, SystemCallError` with `rescue SystemCallError, IOError` into one shared clause while preserving destination-only additions inside the rescue body.
- Revalidated focused smart-merger specs and the full workspace-backed `prism-merge` suite.

## Execution Backlog

### Slice 1 — Expose the shared capability over native Prism ownership
- Add `comment_capability`, `comment_augmenter`, and normalized attachments to file analysis and wrapped nodes.
- Preserve document prelude/postlude behavior through the shared API without changing Ruby-specific semantics.
- Add focused analysis specs proving native Prism comments are surfaced through shared abstractions.

Status: complete on 2026-03-09.

### Slice 2 — Matched and removed Ruby node fallback
- Preserve destination leading and inline comments when matched template-preferred nodes win.
- Preserve or promote comments for removed destination-only nodes when removal is enabled.
- Add focused smart-merger regressions around classes, methods, and nested bodies.

Status: matched-node fallback completed on 2026-03-09; removal behavior still open if/when destination-only removal is enabled.

### Slice 3 — Ruby-specific hard cases
- Reconcile magic comments, shebang handling, and freeze/deduplication behavior with the shared layer.
- Expand recursive body merge regressions to ensure comment association remains stable.
- Add reproducible fixtures only for the highest-risk Ruby comment patterns.

Status: in progress on 2026-03-09. Comment-only header prelude handling, freeze-semantics alignment, recursive-wrapper trailing/inline comment stability, recursive BeginNode clause preservation, recursive BeginNode clause-header inline fallback, recursive BeginNode destination-tail fallback, recursive BeginNode mixed-tail clause merging, recursive BeginNode multi-rescue preservation, recursive BeginNode rescue-signature matching, recursive BeginNode shared-clause body merging, recursive BeginNode shared-clause leading-comment preservation, recursive BeginNode shared-clause footer preservation, recursive BeginNode bare-rescue canonicalization, recursive BeginNode shared-clause fallback comment preservation, recursive BeginNode shared-clause fallback footer preservation, recursive BeginNode freeze-aware clause fallback, and recursive BeginNode rescue-exception order canonicalization are now aligned; any remaining recursive-body work should be limited to newly discovered edge cases.

Current sub-status: header handling, freeze-semantics alignment, recursive-wrapper trailing + inline comment stability, and recursive BeginNode clause preservation + clause-header inline fallback + destination-tail fallback + mixed-tail clause merging + multi-rescue preservation + rescue-signature matching + shared-clause body merging + shared-clause leading-comment preservation + shared-clause footer preservation + bare-rescue canonicalization + shared-clause fallback comment preservation + shared-clause fallback footer preservation + freeze-aware clause fallback + rescue-exception order canonicalization are complete; remaining recursive-body work is now very narrow and likely centered on other wrapper-adjacent edge cases only if new regressions are found.

## Dependencies / Resume Notes
- Start in `lib/prism/merge/file_analysis.rb` and `lib/prism/merge/comment.rb`.
- Treat `psych-merge` as the shared API reference and Prism’s native comment ownership as the precision source.
- Keep magic comments Ruby-specific even if their transport uses shared abstractions.

## Exit Gate For This Plan
- The shared comment API works end-to-end in Ruby without sacrificing Prism-native precision.
- Magic comments, shebangs, and nested body comments remain stable under merge.
