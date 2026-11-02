import { View, div } from "gpui-kit";
import { appHome, exec, notify, setShared, shared, theme } from "herdr";

const ENABLED = "caffeinate.enabled";

export default class Caffeinate extends View {
  init(_props, cx) {
    this.active = null;
    this.running = false;
    this.changing = false;
    this.pending = null;
    this.error = null;
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

  render() {
    const t = theme();
    const label = this.error ? "Caffeinate error" : this.changing || this.active === null ? "Caffeinate…" : this.active ? "Caffeinate on" : "Caffeinate off";
    return div().id("caffeinate").size_full().flex().items_center().justify_center()
      .bg(t.chrome).text_size(11.8).text_color(this.error ? t.blocked : this.active ? t.accent : t.dim)
      .tooltip(this.error || "Keep this Mac awake while Herdr is running. Click to toggle.")
      .cursor_pointer().on_click((_event, cx) => this.toggle(cx))
      .child(label);
  }
}
