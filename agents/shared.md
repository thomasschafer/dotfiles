* If `~/.config/agents/local.md` exists, read it before starting: it covers how this machine differs, such as how software gets installed, and takes precedence over these instructions where they conflict.
    @~/.config/agents/local.md

## Working with me

* You are always welcome to disagree with me, push back when you think I'm making the wrong decisions and otherwise have robust discussions where we may not be immediately aligned. If a question or request of mine seems to rest on a misunderstanding, say what I've likely misunderstood and correct it before acting, even if that means not doing what I asked. I would always rather you did this than quietly went along with something you disagree with, or carried on when I may be misguided.
* Flag issues, even if you end up working around them. For instance, if there is some issue with my local dev setup or an MCP (this is by no means an exhaustive list) that a future agent will run into, it will often make sense to fix this, so point it out to me and we'll discuss.
* If you repeatedly have to do some work, consider whether it can be built into either existing or new tooling. It is often useful for you as an agent to have a tool, even if a human engineer won't use it, so flag any such opportunities.

## Environment

* Never use cloud, managed, remote, or otherwise non-local agents unless I have explicitly signed it off. Local solutions such as sub-agents, including on timers and other local features, are absolutely fine.
* Use sub-agents where it makes sense, such as in a long context chat where we need to make a targeted change and validate it by running tests and so on. Unless I've specified, use the same model as yourself. However, don't use them where the overhead cost would outweigh any benefit: for instance, if you've been asked to review a PR in a fresh chat, it will likely be better to do the review directly.
* I use the Herdr desktop app for local development. When creating new branches, default to worktrees unless I've requested otherwise or if there is a clear reason not to. Worktrees go in `~/.herdr/worktrees/<repo>/<branch>`, with any `/` in the branch name replaced by `-`. If the repo has submodules, run `git submodule update --init --recursive` in the new worktree, as `git worktree add` doesn't.
* Never start, restart or update the herdr-core server (`herdr-core server start|restart`, `hc update`, etc.) from your own shell: the core passes its environment to every terminal, so your variables would leak into all my panes. A new terminal in the Herdr app doesn't help, as it inherits the same environment. Run it in a fresh Terminal.app window instead, with `osascript -e 'tell application "Terminal" to do script "~/.cargo/bin/herdr-core server restart; exit"'`, then check it restarted with `herdr-core server status`.
* Search with `rg` rather than `grep`, including when filtering command output.

## Code

* Only create comments that are necessary to explain or share context for future readers of the code. Never create pointless comments, such as "Increased this because ...", or "breadcrumb" style comments, such as "Matches the old style": comments should be useful in isolation, not a log of how the code has changed during our session. Equally, never remove existing comments unless they are no longer needed; if they become out of date with the code, update them as appropriate.
* Ensure that code is DRY where possible and reasonable. If we can re-use some code the default should be to do so, rather than duplicating. If we need to refactor to make re-use possible then this is fine unless I have explicitly said otherwise.
* Always program defensively. It is far better to fail loudly when an invariant is violated or we're unable to handle something, rather than silently ignoring the issue. Lean on types for this: better to encode an invariant in the type system than to have to perform additional runtime checks (and potentially forget those checks and have a buggy application). However, if encoding a given invariant in types is not possible or practical, then ensure you do add those runtime checks.
* When writing tests, never take shortcuts, such as skipping or weakening a test if something isn't working for you or in our environment. Always communicate issues you're running into and tell me what you need.

## Writing

* When creating new markdown docs, only use title case for headings where it is explicitly required, such as the title of a book; in all other cases, use sentence case. Limit emoji, bold and italics to only where they are genuinely required. When updating existing markdown docs, however, stick to their conventions in preference to these.
* When creating PRs:
    * Do not add a line indicating the AI tool used, such as "Generated with Claude Code".
    * Write the description for a human reviewer who hasn't seen the code, and lead with what changes from the user's (or the API consumer's) perspective rather than how it was built. Also include the *why* behind the change, not just the *what*. Keep it short enough to read in under a minute; only use headings if it's long enough to genuinely need them. Also don't over-use bullet points: a few is fine, but the PR description should not be entirely bullets.
    * Feel free to include diagrams, where it will aid with understanding.
    * In general, leave implementation detail to the diff. Don't list internal function, component or test names, describe refactor mechanics, or report test counts and lint/type-check results, unless there is a clear reason to include such information.
    * Do include what a reviewer can't get from the diff: dependencies on other PRs, merge or deploy ordering, intentional behaviour changes that could look like bugs, and anything a consumer could easily get wrong.
* When updating PR descriptions, first read the current description, as I may have updated it since you last read or wrote it.
