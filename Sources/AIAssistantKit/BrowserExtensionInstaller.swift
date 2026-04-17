import Foundation

public enum BrowserExtensionInstaller {
    public static let bridgeURL = "http://127.0.0.1:48765"

    public static func install() throws -> URL {
        let directory = AppPaths.appSupportDirectory
            .appendingPathComponent("browser-extension", isDirectory: true)
            .appendingPathComponent("chromium", isDirectory: true)

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        try write(file: "manifest.json", to: directory, contents: manifest)
        try write(file: "background.js", to: directory, contents: backgroundJS)
        try write(file: "result.html", to: directory, contents: resultHTML)
        try write(file: "result.js", to: directory, contents: resultJS)
        try write(file: "result.css", to: directory, contents: resultCSS)

        return directory
    }

    private static func write(file: String, to directory: URL, contents: String) throws {
        let url = directory.appendingPathComponent(file)
        try contents.write(to: url, atomically: true, encoding: .utf8)
    }

    private static let manifest = """
    {
      "manifest_version": 3,
      "name": "ClickCLIAssistant",
      "version": "0.1.0",
      "description": "Use local markdown skills from the browser context menu.",
      "permissions": ["contextMenus", "storage"],
      "host_permissions": ["\(bridgeURL)/*"],
      "background": {
        "service_worker": "background.js"
      },
      "browser_specific_settings": {
        "gecko": {
          "id": "click-cli-assistant@local",
          "strict_min_version": "121.0"
        }
      }
    }
    """

    private static let backgroundJS = """
    const ext = globalThis.browser ?? globalThis.chrome;
    const BRIDGE = "\(bridgeURL)";
    const ROOT_ID = "click_assistant_root";
    const SKILL_PREFIX = "click_assistant_skill_";
    const RESULT_KEY = "click_assistant_last_result";
    const skillsByMenuId = new Map();

    function maybePromise(value) {
      if (value && typeof value.then === "function") return value;
      return Promise.resolve(value);
    }

    function callWithCallback(fn, ...args) {
      return new Promise((resolve, reject) => {
        fn(...args, () => {
          const error = ext.runtime?.lastError;
          if (error) {
            reject(new Error(error.message || String(error)));
            return;
          }
          resolve();
        });
      });
    }

    function createMenu(item) {
      try {
        return maybePromise(ext.contextMenus.create(item));
      } catch {
        return callWithCallback(ext.contextMenus.create.bind(ext.contextMenus), item);
      }
    }

    function removeAllMenus() {
      try {
        return maybePromise(ext.contextMenus.removeAll());
      } catch {
        return callWithCallback(ext.contextMenus.removeAll.bind(ext.contextMenus));
      }
    }

    function openTab(url) {
      return maybePromise(ext.tabs.create({ url }));
    }

    function storageSet(value) {
      try {
        return maybePromise(ext.storage.local.set(value));
      } catch {
        return callWithCallback(ext.storage.local.set.bind(ext.storage.local), value);
      }
    }

    async function request(path, options = {}) {
      const response = await fetch(`${BRIDGE}${path}`, options);
      if (!response.ok) {
        const text = await response.text();
        throw new Error(text || `Request failed: ${response.status}`);
      }
      if (response.status === 204) return null;
      return response.json();
    }

    function createRootMenu() {
      createMenu({
        id: ROOT_ID,
        title: "Use Skills",
        contexts: ["selection"]
      });
    }

    function createStatusItem(title) {
      createMenu({
        id: `${ROOT_ID}_status`,
        parentId: ROOT_ID,
        title,
        contexts: ["selection"],
        enabled: false
      });
    }

    function createSkillItems(skills) {
      skillsByMenuId.clear();
      for (const skill of skills) {
        const menuId = `${SKILL_PREFIX}${skill.id}`;
        skillsByMenuId.set(menuId, skill);
        createMenu({
          id: menuId,
          parentId: ROOT_ID,
          title: skill.name,
          contexts: ["selection"]
        });
      }
    }

    async function refreshMenus() {
      await removeAllMenus();
      createRootMenu();
      try {
        const payload = await request("/skills");
        const skills = Array.isArray(payload?.skills) ? payload.skills : [];
        if (skills.length === 0) {
          createStatusItem("No skills found");
        } else {
          createSkillItems(skills);
        }
      } catch {
        createStatusItem("Bridge not running");
      }
    }

    async function handleSkillClick(menuItemId, selectedText) {
      const skill = skillsByMenuId.get(menuItemId);
      if (!skill) {
        await storageSet({
          [RESULT_KEY]: {
            skillName: "Unknown Skill",
            output: "",
            selectedText: selectedText || "",
            error: "Selected skill was not found. Reload the extension and try again."
          }
        });
        await openTab(ext.runtime.getURL("result.html"));
        return;
      }

      if (!selectedText || !selectedText.trim()) {
        await storageSet({
          [RESULT_KEY]: {
            skillName: skill.name,
            output: "",
            selectedText: "",
            error: "Browser did not provide selected text. Select plain text on the page and try again."
          }
        });
        await openTab(ext.runtime.getURL("result.html"));
        return;
      }

      try {
        const payload = await request("/transform", {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ skillId: skill.id, text: selectedText })
        });

        await storageSet({
          [RESULT_KEY]: {
            skillName: payload.skillName || skill.name,
            output: payload.output || "",
            selectedText
          }
        });

        await openTab(ext.runtime.getURL("result.html"));
      } catch (error) {
        await storageSet({
          [RESULT_KEY]: {
            skillName: skill.name,
            output: "",
            selectedText,
            error: error instanceof Error ? error.message : String(error)
          }
        });

        await openTab(ext.runtime.getURL("result.html"));
      }
    }

    ext.runtime.onInstalled.addListener(refreshMenus);
    ext.runtime.onStartup.addListener(refreshMenus);

    ext.contextMenus.onClicked.addListener((info) => {
      if (typeof info.menuItemId !== "string") return;
      if (!info.menuItemId.startsWith(SKILL_PREFIX)) return;
      handleSkillClick(info.menuItemId, info.selectionText || "");
    });

    refreshMenus();
    """

    private static let resultHTML = """
    <!doctype html>
    <html lang="en">
    <head>
      <meta charset="utf-8" />
      <meta name="viewport" content="width=device-width, initial-scale=1" />
      <title>Click Assistant Result</title>
      <link rel="stylesheet" href="result.css" />
    </head>
    <body>
      <main class="container">
        <h1 id="title">Skill Result</h1>
        <p id="meta"></p>
        <div id="error" class="error hidden"></div>
        <textarea id="output" readonly></textarea>
        <button id="copy">Copy Result</button>
      </main>
      <script src="result.js" type="module"></script>
    </body>
    </html>
    """

    private static let resultJS = """
    const ext = globalThis.browser ?? globalThis.chrome;
    const RESULT_KEY = "click_assistant_last_result";

    function maybePromise(value) {
      if (value && typeof value.then === "function") return value;
      return Promise.resolve(value);
    }

    function storageGet(key) {
      try {
        return maybePromise(ext.storage.local.get(key));
      } catch {
        return new Promise((resolve, reject) => {
          ext.storage.local.get(key, (value) => {
            const error = ext.runtime?.lastError;
            if (error) {
              reject(new Error(error.message || String(error)));
              return;
            }
            resolve(value);
          });
        });
      }
    }

    async function loadResult() {
      const stored = await storageGet(RESULT_KEY);
      return stored[RESULT_KEY] || null;
    }

    async function copyOutput(value) {
      await navigator.clipboard.writeText(value);
    }

    function setText(id, value) {
      const node = document.getElementById(id);
      if (!node) return;
      node.textContent = value;
    }

    function setError(message) {
      const node = document.getElementById("error");
      if (!node) return;
      if (!message) {
        node.classList.add("hidden");
        node.textContent = "";
        return;
      }
      node.classList.remove("hidden");
      node.textContent = message;
    }

    async function bootstrap() {
      const result = await loadResult();
      const output = document.getElementById("output");
      const copy = document.getElementById("copy");

      if (!output || !copy) return;

      if (!result) {
        setText("title", "No Result Available");
        setText("meta", "Run a skill from the browser right-click menu.");
        setError("");
        output.value = "";
        copy.disabled = true;
        return;
      }

      setText("title", result.skillName || "Skill Result");
      setText("meta", "Processed selected text through local Ollama.");
      setError(result.error || "");
      output.value = result.output || "";
      copy.disabled = !(result.output || "").trim();

      copy.addEventListener("click", async () => {
        const value = output.value || "";
        if (!value.trim()) return;
        await copyOutput(value);
        copy.textContent = "Copied";
        setTimeout(() => {
          copy.textContent = "Copy Result";
        }, 1200);
      });
    }

    bootstrap();
    """

    private static let resultCSS = """
    :root {
      --bg: #12141a;
      --panel: #1b2029;
      --text: #edf1f8;
      --muted: #9faac2;
      --accent: #1f8f6f;
      --accent-hover: #26ab85;
      --error: #e66f6f;
      --border: #2a3040;
    }

    * {
      box-sizing: border-box;
    }

    body {
      margin: 0;
      font-family: "Avenir Next", "Segoe UI", sans-serif;
      color: var(--text);
      background: radial-gradient(circle at top left, #22324a 0%, var(--bg) 45%);
      min-height: 100vh;
      display: grid;
      place-items: center;
      padding: 24px;
    }

    .container {
      width: min(860px, 100%);
      background: linear-gradient(160deg, rgba(255, 255, 255, 0.03), rgba(255, 255, 255, 0.01));
      border: 1px solid var(--border);
      border-radius: 8px;
      padding: 20px;
      box-shadow: 0 24px 60px rgba(0, 0, 0, 0.35);
    }

    h1 {
      margin: 0 0 6px;
      font-size: clamp(22px, 3vw, 30px);
      letter-spacing: 0;
    }

    #meta {
      margin: 0 0 14px;
      color: var(--muted);
      font-size: 14px;
    }

    textarea {
      width: 100%;
      min-height: 360px;
      max-height: 60vh;
      border-radius: 8px;
      border: 1px solid var(--border);
      background: var(--panel);
      color: var(--text);
      padding: 14px;
      resize: vertical;
      font: 14px/1.5 "SF Mono", Menlo, monospace;
    }

    button {
      margin-top: 14px;
      border: 0;
      border-radius: 8px;
      padding: 10px 14px;
      font-weight: 700;
      letter-spacing: 0;
      background: var(--accent);
      color: #fff;
      cursor: pointer;
      transition: background 160ms ease;
    }

    button:hover {
      background: var(--accent-hover);
    }

    button:disabled {
      background: #3a4256;
      cursor: not-allowed;
    }

    .error {
      margin: 0 0 10px;
      color: var(--error);
      font-size: 14px;
    }

    .hidden {
      display: none;
    }
    """
}
