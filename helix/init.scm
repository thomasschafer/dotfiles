(require "helix/configuration.scm")

(require "cogs/keymaps.scm")

; Scooter
(require "../../Development/Personal/scooter.hx/scooter.scm")
(keymap (global) (normal (ret (q ":scooter"))))

; Smooth scroll
(require "../../Development/Personal/smooth-scroll.hx/smooth-scroll.scm")
(keymap (global) (normal (C-d half-page-down-smooth)))
(keymap (global) (normal (C-u half-page-up-smooth)))
(keymap (global) (normal (pageup page-up-smooth)))
(keymap (global) (normal (pagedown page-down-smooth)))

; Reopen files and splits when herdr restores this pane after a restart
(require "../../Development/Personal/herdr-session.hx/herdr-session.scm")
