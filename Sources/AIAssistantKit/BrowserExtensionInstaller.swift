#if false
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
        try write(file: "content.js", to: directory, contents: contentJS)
        try write(file: "content.css", to: directory, contents: contentCSS)

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
      "version": "0.2.0",
      "description": "Use local markdown skills from the browser context menu.",
      "permissions": ["contextMenus"],
      "host_permissions": ["\(bridgeURL)/*"],
      "background": {
        "service_worker": "background.js"
      },
      "content_scripts": [
        {
          "matches": ["<all_urls>"],
          "js": ["content.js"],
          "css": ["content.css"],
          "run_at": "document_idle"
        }
      ],
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

    function sendMessageToTab(tabId, message) {
      if (typeof tabId !== "number") return Promise.resolve(false);
      try {
        return maybePromise(ext.tabs.sendMessage(tabId, message))
          .then(() => true)
          .catch(() => false);
      } catch {
        return new Promise((resolve) => {
          ext.tabs.sendMessage(tabId, message, () => {
            const error = ext.runtime?.lastError;
            resolve(!error);
          });
        });
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

    function parseSkillId(menuItemId) {
      if (typeof menuItemId !== "string") return null;
      if (!menuItemId.startsWith(SKILL_PREFIX)) return null;
      return menuItemId.slice(SKILL_PREFIX.length) || null;
    }

    async function resolveSkill(menuItemId) {
      const cached = skillsByMenuId.get(menuItemId);
      if (cached) return cached;

      const skillId = parseSkillId(menuItemId);
      if (!skillId) return null;

      const payload = await request("/skills");
      const skills = Array.isArray(payload?.skills) ? payload.skills : [];
      const skill = skills.find((item) => item.id === skillId) || null;
      if (skill) {
        skillsByMenuId.set(menuItemId, skill);
      }
      return skill;
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

    async function showLoading(tabId, skillName, selectedText) {
      await sendMessageToTab(tabId, {
        type: "click_assistant_show_popup",
        status: "loading",
        skillName,
        selectedText,
        output: ""
      });
    }

    async function showResult(tabId, skillName, selectedText, output, error) {
      await sendMessageToTab(tabId, {
        type: "click_assistant_show_popup",
        status: error ? "error" : "success",
        skillName,
        selectedText,
        output: output || "",
        error: error || ""
      });
    }

    async function handleSkillClick(menuItemId, selectedText, tabId) {
      let skill = null;
      try {
        skill = await resolveSkill(menuItemId);
      } catch {
        skill = null;
      }

      if (!skill) {
        await showResult(tabId, "Unknown Skill", selectedText || "", "", "Selected skill was not found. Reload the extension and try again.");
        return;
      }

      if (!selectedText || !selectedText.trim()) {
        await showResult(tabId, skill.name, "", "", "Browser did not provide selected text. Select plain text on the page and try again.");
        return;
      }

      await showLoading(tabId, skill.name, selectedText);

      try {
        const payload = await request("/transform", {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ skillId: skill.id, text: selectedText })
        });

        await showResult(
          tabId,
          payload.skillName || skill.name,
          selectedText,
          payload.output || "",
          ""
        );
      } catch (error) {
        await showResult(
          tabId,
          skill.name,
          selectedText,
          "",
          error instanceof Error ? error.message : String(error)
        );
      }
    }

    ext.runtime.onInstalled.addListener(refreshMenus);
    ext.runtime.onStartup.addListener(refreshMenus);

    ext.contextMenus.onClicked.addListener((info, tab) => {
      if (typeof info.menuItemId !== "string") return;
      if (!info.menuItemId.startsWith(SKILL_PREFIX)) return;
      const tabId = typeof tab?.id === "number" ? tab.id : null;
      handleSkillClick(info.menuItemId, info.selectionText || "", tabId);
    });

    refreshMenus();
    """

    private static let contentJS = """
    const ROOT_ID = "click-assistant-popup-root";
    let root = null;
    let lastSelection = "";
    let shownAt = 0;

    function ensureRoot() {
      if (root) return root;
      root = document.createElement("div");
      root.id = ROOT_ID;
      root.className = "click-assistant-popover hidden";
      root.innerHTML = `
        <div class="click-assistant-popover-arrow"></div>
        <div class="click-assistant-popover-title" id="click-assistant-title">Use Skills</div>
        <div class="click-assistant-popover-divider"></div>
        <div class="click-assistant-popover-body" id="click-assistant-body"></div>
        <div class="click-assistant-popover-actions">
          <button id="click-assistant-replace" class="click-assistant-btn">Replace</button>
          <button id="click-assistant-copy" class="click-assistant-btn">Copy</button>
        </div>
      `;
      document.documentElement.appendChild(root);

      const replace = root.querySelector("#click-assistant-replace");
      const copy = root.querySelector("#click-assistant-copy");

      replace?.addEventListener("click", () => replaceSelection());
      copy?.addEventListener("click", async () => {
        const body = root.querySelector("#click-assistant-body");
        const value = body?.textContent || "";
        if (!value.trim()) return;
        await navigator.clipboard.writeText(value);
        copy.textContent = "Copied";
        setTimeout(() => { copy.textContent = "Copy"; }, 1000);
      });

      document.addEventListener("mousedown", (event) => {
        if (!root || root.classList.contains("hidden")) return;
        if (Date.now() - shownAt < 320) return;
        if (root.contains(event.target)) return;
        hidePopup();
      }, true);

      document.addEventListener("keydown", (event) => {
        if (event.key === "Escape") {
          hidePopup();
        }
      });

      return root;
    }

    function hidePopup() {
      const node = ensureRoot();
      node.classList.add("hidden");
    }

    function currentSelectionRect() {
      const selection = window.getSelection();
      if (selection && selection.rangeCount > 0) {
        const text = selection.toString().trim();
        if (text) lastSelection = text;
        const range = selection.getRangeAt(0);
        const rect = range.getBoundingClientRect();
        if (rect && (rect.width > 0 || rect.height > 0)) {
          return rect;
        }
      }
      return null;
    }

    function positionPopup(node) {
      const rect = currentSelectionRect();
      const vw = window.innerWidth;
      const vh = window.innerHeight;
      const width = Math.min(760, Math.max(340, Math.floor(vw * 0.48)));
      node.style.width = `${width}px`;

      const popRect = node.getBoundingClientRect();
      const gap = 12;

      let left = window.scrollX + (vw - width) / 2;
      let top = window.scrollY + 20;
      let arrowLeft = width / 2;

      if (rect) {
        left = window.scrollX + rect.left + (rect.width - width) / 2;
        top = window.scrollY + rect.top - popRect.height - gap;
        if (top < window.scrollY + 12) {
          top = window.scrollY + rect.bottom + gap;
          node.classList.add("below");
        } else {
          node.classList.remove("below");
        }
        arrowLeft = window.scrollX + rect.left + rect.width / 2 - left;
      } else {
        node.classList.remove("below");
      }

      const minLeft = window.scrollX + 12;
      const maxLeft = window.scrollX + vw - width - 12;
      left = Math.max(minLeft, Math.min(maxLeft, left));

      const maxTop = window.scrollY + vh - popRect.height - 12;
      top = Math.max(window.scrollY + 12, Math.min(maxTop, top));

      node.style.left = `${left}px`;
      node.style.top = `${top}px`;

      const arrow = node.querySelector(".click-assistant-popover-arrow");
      if (arrow) {
        const minArrow = 20;
        const maxArrow = width - 20;
        arrowLeft = Math.max(minArrow, Math.min(maxArrow, arrowLeft));
        arrow.style.left = `${arrowLeft}px`;
      }
    }

    function setPopupMessage(title, body, status) {
      const node = ensureRoot();
      const titleNode = node.querySelector("#click-assistant-title");
      const bodyNode = node.querySelector("#click-assistant-body");
      const replace = node.querySelector("#click-assistant-replace");
      const copy = node.querySelector("#click-assistant-copy");

      titleNode.textContent = title || "Use Skills";
      bodyNode.textContent = body || "";

      node.classList.remove("loading");
      node.classList.remove("error");

      if (status === "loading") {
        node.classList.add("loading");
        replace.setAttribute("disabled", "disabled");
        copy.setAttribute("disabled", "disabled");
      } else if (status === "error") {
        node.classList.add("error");
        replace.setAttribute("disabled", "disabled");
        copy.removeAttribute("disabled");
      } else {
        replace.removeAttribute("disabled");
        copy.removeAttribute("disabled");
      }

      node.classList.remove("hidden");
      shownAt = Date.now();
      positionPopup(node);
    }

    function replaceSelection() {
      const node = ensureRoot();
      const body = node.querySelector("#click-assistant-body");
      const value = body?.textContent || "";
      if (!value.trim()) return;

      const active = document.activeElement;
      if (active && (active.tagName === "TEXTAREA" || active.tagName === "INPUT")) {
        const start = active.selectionStart ?? 0;
        const end = active.selectionEnd ?? start;
        const current = active.value || "";
        active.value = current.slice(0, start) + value + current.slice(end);
        const caret = start + value.length;
        active.setSelectionRange(caret, caret);
        return;
      }

      document.execCommand("insertText", false, value);
    }

    function onRuntimeMessage(message) {
      if (!message || message.type !== "click_assistant_show_popup") return;

      if (message.selectedText && message.selectedText.trim()) {
        lastSelection = message.selectedText.trim();
      }

      if (message.status === "loading") {
        setPopupMessage(message.skillName || "Use Skills", "Working on it...", "loading");
        return;
      }

      if (message.status === "error") {
        setPopupMessage(message.skillName || "Use Skills", message.error || "Unknown error", "error");
        return;
      }

      setPopupMessage(message.skillName || "Use Skills", message.output || "", "success");
    }

    const ext = globalThis.browser ?? globalThis.chrome;
    ext.runtime.onMessage.addListener(onRuntimeMessage);
    """

    private static let contentCSS = """
    .click-assistant-popover {
      position: absolute;
      z-index: 2147483647;
      border-radius: 20px;
      border: 1px solid rgba(255, 255, 255, 0.16);
      background: linear-gradient(160deg, rgba(40, 44, 54, 0.96), rgba(24, 27, 33, 0.96));
      color: #f2f6ff;
      backdrop-filter: blur(14px);
      box-shadow: 0 20px 44px rgba(0, 0, 0, 0.42);
      padding: 16px;
      font-family: "SF Pro Text", "Avenir Next", "Segoe UI", sans-serif;
    }

    .click-assistant-popover.hidden {
      display: none;
    }

    .click-assistant-popover-arrow {
      position: absolute;
      bottom: -7px;
      width: 14px;
      height: 14px;
      transform: rotate(45deg);
      background: rgba(30, 34, 42, 0.96);
      border-right: 1px solid rgba(255, 255, 255, 0.16);
      border-bottom: 1px solid rgba(255, 255, 255, 0.16);
      margin-left: -7px;
    }

    .click-assistant-popover.below .click-assistant-popover-arrow {
      top: -7px;
      bottom: auto;
      border-right: none;
      border-bottom: none;
      border-left: 1px solid rgba(255, 255, 255, 0.16);
      border-top: 1px solid rgba(255, 255, 255, 0.16);
    }

    .click-assistant-popover-title {
      font-size: 18px;
      line-height: 1.2;
      font-weight: 700;
      letter-spacing: 0;
      margin-bottom: 10px;
    }

    .click-assistant-popover-divider {
      height: 1px;
      background: rgba(255, 255, 255, 0.12);
      margin-bottom: 12px;
    }

    .click-assistant-popover-body {
      font-size: 15px;
      line-height: 1.45;
      font-weight: 500;
      letter-spacing: 0;
      white-space: pre-wrap;
      max-height: 220px;
      overflow: auto;
      margin-bottom: 12px;
      word-break: break-word;
    }

    .click-assistant-popover-actions {
      display: flex;
      gap: 10px;
      align-items: center;
    }

    .click-assistant-btn {
      border: 1px solid rgba(255, 255, 255, 0.14);
      background: rgba(255, 255, 255, 0.08);
      color: #eff4ff;
      border-radius: 10px;
      padding: 8px 12px;
      font-size: 13px;
      font-weight: 600;
      letter-spacing: 0;
      cursor: pointer;
    }

    .click-assistant-btn[disabled] {
      opacity: 0.45;
      cursor: not-allowed;
    }

    .click-assistant-popover.loading .click-assistant-popover-body {
      color: #c5d2ea;
      font-style: italic;
    }

    .click-assistant-popover.error .click-assistant-popover-body {
      color: #ff9e9e;
    }

    @media (max-width: 640px) {
      .click-assistant-popover {
        width: calc(100vw - 24px) !important;
      }
      .click-assistant-popover-title {
        font-size: 16px;
      }
      .click-assistant-popover-body {
        font-size: 14px;
      }
    }
    """
}

#endif
