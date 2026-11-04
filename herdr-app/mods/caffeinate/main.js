import { View, div } from "gpui-kit";
import { appHome, exec, notify, props, run, setShared, shared, theme } from "herdr";

const ENABLED = "caffeinate.enabled";
const DEFAULT_PADDING = [12, 12];

// The sizing props, { block, padding: [left, right] }, or an error saying what's wrong with them.
// With a block, the mod resizes that layout node to fit its label plus the padding, so the
// layout can space it evenly from its neighbours.
function sizing() {
  const { block = null, padding = DEFAULT_PADDING } = props() ?? {};
  if (block !== null && (typeof block !== "string" || block === "")) {
    return { error: `The layout gives caffeinate a block of ${JSON.stringify(block)}, not a node id.` };
  }
  if (!Array.isArray(padding) || padding.length !== 2 || !padding.every((n) => Number.isFinite(n) && n >= 0)) {
    return { error: `The layout gives caffeinate a padding of ${JSON.stringify(padding)}, not [left, right] in px.` };
  }
  return { block, padding };
}

export default class Caffeinate extends View {
  init(_props, cx) {
    this.active = null;
    this.running = false;
    this.changing = false;
    this.pending = null;
    this.error = null;
    this.fitted = null;
    this.control(shared(ENABLED) === false ? "stop" : "start", cx);
    cx.timer.every(30000, (cx) => this.control("status", cx));
  }

  control(action, cx) {
    if (action !== "status") {
      this.pending = action;
      this.changing = true;
      cx.notify();
    }
    if (this.running) return;
    this.running = true;
    cx.spawn(async (cx) => {
      let next = this.pending ?? "status";
      this.pending = null;
      while (next !== null) {
        const previousActive = this.active;
        const previousError = this.error;
        try {
          const result = await exec("/bin/sh", [`${appHome()}/mods/caffeinate/control.sh`, next]);
          if (result.code !== 0) throw new Error(result.stderr.trim() || `Helper exited with status ${result.code}`);
          const state = result.stdout.trim();
          if (state !== "on" && state !== "off") throw new Error(`Unexpected caffeinate state: ${state}`);
          this.active = state === "on";
          this.error = null;
        } catch (error) {
          const message = String(error);
          if (this.error !== message) notify({ title: "Caffeinate failed", body: message, level: "error" });
          this.error = message;
        }
        if (this.active !== previousActive || this.error !== previousError) cx.notify();
        next = this.pending;
        this.pending = null;
      }
      this.running = false;
      if (this.changing) {
        this.changing = false;
        cx.notify();
      }
    });
  }

  toggle(cx) {
    const enabled = shared(ENABLED) === false;
    setShared(ENABLED, enabled);
    this.control(enabled ? "start" : "stop", cx);
  }

  // Resizes the layout node to `px`, when that changes. The app keeps the size with the
  // layout's clicks, not in its file.
  fit(block, px) {
    px = Math.ceil(px);
    if (px === this.fitted) return;
    this.fitted = px;
    run("layout.resize", { id: block, px });
  }

  render() {
    const t = theme();
    const { block, padding: [left, right] = DEFAULT_PADDING, error: sizingError } = sizing();
    const error = [this.error, sizingError].filter(Boolean).join("\n");
    const label = this.error ? "Caffeinate error" : this.changing || this.active === null ? "Caffeinate…" : this.active ? "Caffeinate on" : "Caffeinate off";
    return div().id("caffeinate").size_full().flex().items_center().justify_center().pl(left).pr(right)
      .bg(t.chrome).text_size(11.8).text_color(error ? t.blocked : this.active ? t.accent : t.dim)
      .tooltip(error || "Keep this Mac awake while Herdr is running. Click to toggle.")
      .cursor_pointer().on_click((_event, cx) => this.toggle(cx))
      .child(
        div().id("caffeinate-label").flex_none()
          .when(Boolean(block), (el) => el.on_size_change((size) => this.fit(block, size.width + left + right)))
          .child(label),
      );
  }
}
