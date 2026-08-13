1. NEVER use cloud, managed, remote, or otherwise non-local agents unless I have explicitly signed it off. Local solutions such as sub-agents, including on timers and other local features, are absolutely fine and can be used whenever you'd like.
1. I use herdr for local development, so when creating worktrees please always use the `herdr` CLI.
1. NEVER create pointless comments, such as "Increased this because ...". Also don't create "breadcrumb" style comments, such as "Matches the old style" - comments should be useful in isolation, not a log of how the code has changed during our session. ONLY create comments that are absolutely necessary to explain or share context for future readers of the code.
1. NEVER remove comments unless they are no longer needed. If they become out of date with the code then update the comments as appropriate. The rule above to not add pointless comments does not mean you should delete all existing comments.
1. When creating markdown docs:
    1. ONLY use title case for headings where it is explicitly required, such as the title of a book. In all other cases, use sentence case.
    1. Limit emoji use to only where it is genuinely required.
    1. Limit use of bold and italics to only where emphasis is genuinely required.
1. When updating markdown docs, stick to the conventions in preference to the above.
1. When writing tests:
    1. NEVER take shortcuts, such as skipping a test case if something isn't working for you or in our environment. Always communicate issues you're running into and tell me what you need.
1. Ensure that code is DRY where possible and reasonable. If we can re-use some code the default should be to do so, rather than duplicating. If we need to refactor to make re-use possible then this is fine unless I have explicitly said otherwise.
1. Always program defensively. It is far better to fail loudly when an invariant is violated or we're unable to handle something, rather than silently ignoring the issue.
1. Lean on types to improve correctness and safety: better to encode an invariant in the type system that have to perform additional runtime checks (and potentially forget those checks and have a buggy application). However, if encoding a given invariant in types is not possible or practical, then ensure you do add those runtime checks.
1. When creating PRs:
    1. Do not add a line indicating the AI tool used, such as "Generated with Claude Code".
    1. Write the description for a human reviewer who hasn't seen the code, and lead with what changes from the user's (or the API consumer's) perspective rather than how it was built. Keep it short enough to read in under a minute; only use headings if it's long enough to genuinely need them.
    1. Leave implementation detail to the diff. Don't list internal function, component or test names, describe refactor mechanics, or report test counts and lint/type-check results.
    1. Do include what a reviewer can't get from the diff: dependencies on other PRs, merge or deploy ordering, intentional behaviour changes that could look like bugs, and anything a consumer could easily get wrong. Follow-up work that's tracked elsewhere doesn't need repeating.
1. When updating PR descriptions, please first read the current description, as I may have updated it since you last read or wrote it.
