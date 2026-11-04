import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";
import { SourceTextModule, SyntheticModule } from "node:vm";

const source = await readFile(new URL("../mods/caffeinate/main.js", import.meta.url), "utf8");

async function harness(storage = new Map(), props = {}) {
  const actions = [];
  const notifications = [];
  const resizes = [];
  const tasks = [];
  let refresh;
  let redraws = 0;
  let execute = async (action) => ({ code: 0, stdout: action === "stop" ? "off" : "on", stderr: "" });
  const cx = {
    notify() { redraws++; },
    spawn(task) { tasks.push(task(cx)); },
    timer: { every(_interval, callback) { refresh = () => callback(cx); } },
  };
  // An element builder that records what the mod set on it.
  function div() {
    const result = { children: [] };
    const builder = new Proxy(result, {
      get(target, key) {
        if (key === "set") return target;
        return (...args) => {
          if (key === "child") target.children.push(args[0]);
          else if (key === "when") return args[0] ? args[1](builder) : builder;
          else target[key] = args[0];
          return builder;
        };
      },
    });
    return builder;
  }
  const exports = {
    "gpui-kit": { View: class {}, div },
    herdr: {
      appHome: () => "/test-home",
      exec: async (_program, args) => {
        const action = args.at(-1);
        actions.push(action);
        return execute(action);
      },
      notify: (message) => notifications.push(message),
      props: () => props,
      run: (name, args) => { resizes.push([name, args]); return null; },
      shared: (key) => storage.get(key),
      setShared: (key, value) => storage.set(key, value),
      theme: () => ({}),
    },
  };
  const module = new SourceTextModule(source);
  await module.link((name) => {
    assert.ok(Object.hasOwn(exports, name), `Unexpected import: ${name}`);
    return new SyntheticModule(Object.keys(exports[name]), function () {
      for (const [key, value] of Object.entries(exports[name])) this.setExport(key, value);
    });
  });
  await module.evaluate();
  const view = new module.namespace.default();
  return {
    actions, notifications, resizes, view,
    init: () => view.init({}, cx),
    toggle: () => view.toggle(cx),
    refresh: () => refresh(),
    settle: async () => { while (tasks.length) await tasks.shift(); },
    execute: (fn) => { execute = fn; },
    redraws: () => redraws,
    root: () => view.render().set,
    label: () => view.render().set.children[0].set.children[0],
  };
}

test("starts by default and remembers off across fresh mod instances", async () => {
  const storage = new Map();
  const first = await harness(storage);
  first.init();
  await first.settle();
  assert.deepEqual(first.actions, ["start"]);
  first.toggle();
  await first.settle();
  assert.equal(first.label(), "Caffeinate off");
  const reloaded = await harness(storage);
  reloaded.init();
  await reloaded.settle();
  assert.deepEqual(reloaded.actions, ["stop"]);
  assert.equal(reloaded.label(), "Caffeinate off");
});

test("an unchanged background check does not change the label or redraw", async () => {
  const h = await harness();
  h.init();
  await h.settle();
  const redraws = h.redraws();
  h.refresh();
  assert.equal(h.label(), "Caffeinate on");
  await h.settle();
  assert.equal(h.redraws(), redraws);
});

test("a click during a background check runs after it completes", async () => {
  const h = await harness();
  h.init();
  await h.settle();
  let finish;
  h.execute((action) => action === "status"
    ? new Promise((resolve) => { finish = resolve; })
    : Promise.resolve({ code: 0, stdout: "off", stderr: "" }));
  h.refresh();
  h.toggle();
  assert.deepEqual(h.actions, ["start", "status"]);
  finish({ code: 0, stdout: "on", stderr: "" });
  await h.settle();
  assert.deepEqual(h.actions, ["start", "status", "stop"]);
  assert.equal(h.label(), "Caffeinate off");
});

test("rapid clicks retain the latest requested state", async () => {
  const h = await harness();
  h.init();
  await h.settle();
  let finish;
  h.execute((action) => action === "status"
    ? new Promise((resolve) => { finish = resolve; })
    : Promise.resolve({ code: 0, stdout: "on", stderr: "" }));
  h.refresh();
  h.toggle();
  h.toggle();
  finish({ code: 0, stdout: "on", stderr: "" });
  await h.settle();
  assert.deepEqual(h.actions, ["start", "status", "start"]);
  assert.equal(h.label(), "Caffeinate on");
});

test("invalid helper output is visible, deduplicated, and recoverable", async () => {
  const h = await harness();
  h.execute(async () => ({ code: 0, stdout: "unexpected", stderr: "" }));
  h.init();
  await h.settle();
  assert.equal(h.label(), "Caffeinate error");
  assert.match(h.notifications[0].body, /Unexpected caffeinate state/);
  h.refresh();
  await h.settle();
  assert.equal(h.notifications.length, 1);
  h.execute(async () => ({ code: 0, stdout: "on", stderr: "" }));
  h.refresh();
  await h.settle();
  assert.equal(h.label(), "Caffeinate on");
});

test("helper failures expose stderr and allow another action", async () => {
  const h = await harness();
  h.execute(async () => ({ code: 1, stdout: "", stderr: "lock unavailable" }));
  h.init();
  await h.settle();
  assert.equal(h.notifications[0].body, "Error: lock unavailable");
  h.execute(async () => ({ code: 0, stdout: "off", stderr: "" }));
  h.toggle();
  await h.settle();
  assert.equal(h.label(), "Caffeinate off");
});

test("with a block, it sizes that layout node to its label plus the padding", async () => {
  const h = await harness(new Map(), { block: "caffeinate", padding: [16, 14] });
  h.init();
  await h.settle();
  const root = h.root();
  assert.deepEqual([root.pl, root.pr], [16, 14]);
  const label = root.children[0].set;
  label.on_size_change({ width: 80.2, height: 14 });
  label.on_size_change({ width: 80.4, height: 14 });
  assert.deepEqual(h.resizes, [["layout.resize", { id: "caffeinate", px: 111 }]]);
});

test("without a block, it leaves its layout node's size alone", async () => {
  const h = await harness();
  h.init();
  await h.settle();
  assert.equal(h.root().children[0].set.on_size_change, undefined);
});

test("invalid sizing props show as an error", async () => {
  const h = await harness(new Map(), { padding: [16] });
  h.init();
  await h.settle();
  assert.match(h.root().tooltip, /^The layout gives caffeinate a padding of \[16\], not \[left, right\] in px\.$/);
  assert.equal(h.label(), "Caffeinate on");
});
