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

    $"> ($dir_segment)($git_segment)"
}
$env.PROMPT_COMMAND = { create_left_prompt }

def prompt_indicator [] {
    $"(ansi reset) $ "
}
$env.PROMPT_INDICATOR_VI_INSERT = { prompt_indicator }
$env.PROMPT_INDICATOR_VI_NORMAL = { prompt_indicator }

$env.PROMPT_COMMAND_RIGHT = ""

$env.config = {
    color_config: {
        shape_garbage: { fg: "red" attr: b}
    }

    cursor_shape: {
        vi_insert: line
        vi_normal: block
    }

    edit_mode: 'vi'

    show_banner: false
}
