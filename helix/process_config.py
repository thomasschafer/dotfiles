import argparse
import toml


def process_config(input_file: str) -> str:
    with open(input_file, "r") as file:
        config = toml.load(file)

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
args = parser.parse_args()

result = process_config(args.input_file)
print(result)
