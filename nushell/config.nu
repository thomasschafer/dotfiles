$env.config.edit_mode = 'vi'

def create_left_prompt [] {
    let dir_segment = $"(ansi '#a6da95')(pwd | path basename)(ansi reset)"

    use std
    let git_current_ref = try {
        git rev-parse --abbrev-ref HEAD e> (std null-device)
    } catch {
        ""
    }
    let git_segment = if ($git_current_ref != "") {
        $" \(($"(ansi '#91d7e3')($git_current_ref)(ansi reset)")\)"
    }

    $"($dir_segment)($git_segment)"
}

$env.PROMPT_COMMAND = { create_left_prompt }
$env.PROMPT_INDICATOR_VI_INSERT = $"(ansi white) >(ansi reset) "
$env.PROMPT_INDICATOR_VI_NORMAL = $"(ansi white) $(ansi reset) "
$env.PROMPT_COMMAND_RIGHT = ""

$env.config.show_banner = false
