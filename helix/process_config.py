import argparse
import toml


def process_config(input_file: str, is_darwin: bool) -> str:
    with open(input_file, "r") as file:
        content = file.read()

    variables = {
        "CURRENT_PATH": "$([ '%{buffer_name}' = '[scratch]' ] && echo $PWD || (realpath '%{buffer_name}' 2>/dev/null || echo '%{buffer_name}'))",
        "TMUX_WINDOW": "tmux new-window -e HELIX_PANE=$TMUX_PANE",
    }
    for var_name, var_value in variables.items():
        content = content.replace(f"${{{var_name}}}", var_value)

    if is_darwin:
        content = content.replace("${CLIPBOARD_PROVIDER}", "pasteboard")
        content = content.replace("${COPY_CMD}", "pbcopy")
    else:
        content = content.replace("${CLIPBOARD_PROVIDER}", "terminal")
        content = content.replace("${COPY_CMD}", "xclip -selection clipboard")

    config = toml.loads(content)

    keys_config = config.get("keys", {})
    normal_and_select = keys_config.pop("normal-and-select", {})

    if normal_and_select:
        for key in ["normal", "select"]:
            if key not in keys_config:
                keys_config[key] = {}
            keys_config[key].update(normal_and_select)

    return toml.dumps(config)


parser = argparse.ArgumentParser(description="Process Helix config files.")
parser.add_argument(
    "input_file", type=str, help="Input file name of the custom TOML configuration."
)
parser.add_argument(
    "--darwin", action="store_true", help="Use macOS-specific settings."
)
args = parser.parse_args()

result = process_config(args.input_file, args.darwin)
print(result)
