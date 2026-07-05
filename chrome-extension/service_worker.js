const HOST_NAME = "com.arel.focus.bridge";
const HEARTBEAT_ALARM = "arelFocusHeartbeat";
const HEARTBEAT_MINUTES = 1;
const FAVICON_SIZE = 32;
const OPEN_TAB_FAVICON_DATA_LIMIT = 12;
const PROFILE_ID_KEY = "arelFocusProfileID";
const BLOCK_RULE_ID_START = 4000;
const FAVICON_EVENT_TYPES = new Set(["tabActivated", "tabCreated", "tabUpdated", "windowFocused", "startup", "installed", "serviceWorkerStarted"]);
let port = null;
let profileIDPromise = null;
const faviconDataCache = new Map();
const sentFaviconDataKeys = new Set();
let lastSentSignature = null;
let lastSentAt = 0;

function domainFromUrl(url) {
  try {
    return new URL(url).hostname.replace(/^www\./, "");
  } catch {
    return null;
  }
}

function connect() {
  if (port) return port;

  try {
    port = chrome.runtime.connectNative(HOST_NAME);
    port.onMessage.addListener((message) => {
      if (message?.blockConfig) {
        applyBlockConfig(message.blockConfig);
      }
    });
    port.onDisconnect.addListener(() => {
      const error = chrome.runtime.lastError;
      if (error) {
        console.debug("Arel Focus native bridge disconnected:", error.message);
      }
      port = null;
    });
  } catch (error) {
    port = null;
  }

  return port;
}

function normalizeDomain(value) {
  if (!value) return null;
  try {
    const candidate = value.includes("://") ? value : `https://${value}`;
    return new URL(candidate).hostname.replace(/^www\./, "").toLowerCase();
  } catch {
    return String(value).trim().replace(/^www\./, "").toLowerCase();
  }
}

// Latest Focus Hour context, kept so the block page redirect carries copy and
// so the "Allow for this session" button knows which session to update.
let focusContext = { targetName: "", profileLabel: "", sessionID: "" };

// Domains the user temp-allowed via the block page, for the CURRENT session only.
// Subtracted from every block-config apply so a stale push from the app (whose
// ~2s poll hasn't processed the allow yet) can't re-block them. Reset when the
// session changes or blocking ends. `lastBlockConfig` lets the allow handler
// recompute the rules immediately instead of waiting for the next push.
let sessionAllowed = new Set();
let allowSessionId = "";
let lastBlockConfig = null;

function blockedPageUrl(domain) {
  const url = new URL(chrome.runtime.getURL("blocked.html"));
  url.searchParams.set("domain", domain);
  url.searchParams.set("target", focusContext.targetName || "");
  url.searchParams.set("profile", focusContext.profileLabel || "");
  url.searchParams.set("session", focusContext.sessionID || "");
  return url.toString();
}

async function applyBlockConfig(config) {
  lastBlockConfig = config;
  const enabled = Boolean(config.blockingEnabled);

  const focus = config.focus ?? {};
  focusContext = {
    targetName: focus.target_name ?? "",
    profileLabel: focus.profile_label ?? "",
    sessionID: focus.session_id ?? ""
  };

  // Reset per-session temp-allows when the session changes or blocking ends.
  if (!enabled || focusContext.sessionID !== allowSessionId) {
    sessionAllowed = new Set();
    allowSessionId = enabled ? focusContext.sessionID : "";
  }

  const domains = [...new Set((config.blockedDomains ?? []).map(normalizeDomain).filter(Boolean))]
    .filter((domain) => !sessionAllowed.has(domain))
    .slice(0, 200);

  const existing = await chrome.declarativeNetRequest.getDynamicRules();
  const removeRuleIds = existing
    .filter((rule) => rule.id >= BLOCK_RULE_ID_START && rule.id < BLOCK_RULE_ID_START + 500)
    .map((rule) => rule.id);

  // Redirect blocked main_frames to the branded block page instead of a hard
  // block (which shows the browser's default error). Each rule is domain-specific
  // so the redirect URL carries the exact blocked domain plus session copy.
  const addRules = enabled ? domains.map((domain, index) => ({
    id: BLOCK_RULE_ID_START + index,
    priority: 1,
    action: {
      type: "redirect",
      redirect: { url: blockedPageUrl(domain) }
    },
    condition: {
      urlFilter: `||${domain}^`,
      resourceTypes: ["main_frame"]
    }
  })) : [];

  try {
    await chrome.declarativeNetRequest.updateDynamicRules({
      removeRuleIds,
      addRules
    });
  } catch (error) {
    console.debug("Arel Focus block rule update failed:", error.message);
  }

  // declarativeNetRequest only redirects NEW navigations — a tab already sitting on
  // a blocked site when the session starts would stay fully usable. Proactively
  // redirect any open blocked tab to the branded block page so the block is felt
  // immediately, not just on the next reload.
  if (enabled && domains.length) {
    await redirectOpenBlockedTabs(domains);
  }
}

async function redirectOpenBlockedTabs(domains) {
  let tabs;
  try {
    tabs = await chrome.tabs.query({});
  } catch {
    return;
  }

  for (const tab of tabs) {
    if (!tab.id || !isTrackablePageUrl(tab.url)) continue;
    const host = domainFromUrl(tab.url);
    if (!host) continue;
    const match = domains.find((domain) => host === domain || host.endsWith(`.${domain}`));
    if (match) {
      chrome.tabs.update(tab.id, { url: blockedPageUrl(match) });
    }
  }
}

// The block page's "Allow {domain} for this session" button sends this message.
// We forward it to the native host as a control message; the host writes an
// update_focus_hour command that the app consumes and re-emits block-config.
chrome.runtime.onMessage.addListener((message, _sender, sendResponse) => {
  if (message?.type !== "focusAllowDomain") return false;

  (async () => {
    const domain = normalizeDomain(message.domain);
    const sessionID = message.session || focusContext.sessionID;
    if (!domain || !sessionID) {
      sendResponse({ ok: false });
      return;
    }

    // Allow the domain locally RIGHT NOW so the block page's retry navigation
    // succeeds immediately. The native round-trip (below) only persists it in
    // the app's session state + telemetry — it must not gate the unblock, because
    // the app's ~2s poll + re-push is far slower than the page's retry.
    sessionAllowed.add(domain);
    if (lastBlockConfig) {
      await applyBlockConfig(lastBlockConfig);
    }

    const nativePort = connect();
    if (nativePort) {
      nativePort.postMessage({ type: "focusAllowDomain", domain, sessionID });
    }
    // The local allow already took effect, so report success regardless.
    sendResponse({ ok: true });
  })();

  return true;
});

function isTrackablePageUrl(url) {
  return Boolean(url)
    && !url.startsWith("chrome://")
    && !url.startsWith("chrome-extension://")
    && !url.startsWith("edge://")
    && !url.startsWith("about:");
}

function base64FromBytes(bytes) {
  let binary = "";
  const chunkSize = 0x8000;

  for (let index = 0; index < bytes.length; index += chunkSize) {
    binary += String.fromCharCode(...bytes.subarray(index, index + chunkSize));
  }

  return btoa(binary);
}

function chromeFaviconUrl(pageUrl) {
  const url = new URL(chrome.runtime.getURL("/_favicon/"));
  url.searchParams.set("pageUrl", pageUrl);
  url.searchParams.set("size", String(FAVICON_SIZE));
  return url.toString();
}

async function faviconDataUrl(pageUrl) {
  if (!isTrackablePageUrl(pageUrl)) return null;
  if (faviconDataCache.has(pageUrl)) return faviconDataCache.get(pageUrl);

  try {
    const response = await fetch(chromeFaviconUrl(pageUrl));
    if (!response.ok) return null;

    const bytes = new Uint8Array(await response.arrayBuffer());
    if (!bytes.length) return null;

    const contentType = response.headers.get("content-type") ?? "image/png";
    const dataURL = `data:${contentType};base64,${base64FromBytes(bytes)}`;
    faviconDataCache.set(pageUrl, dataURL);
    return dataURL;
  } catch {
    return null;
  }
}

async function faviconDataUrlOnce(pageUrl, includeFaviconData) {
  if (!includeFaviconData || !pageUrl) return null;
  if (sentFaviconDataKeys.has(pageUrl)) return null;

  const dataURL = await faviconDataUrl(pageUrl);
  if (dataURL) {
    sentFaviconDataKeys.add(pageUrl);
  }
  return dataURL;
}

async function tabPayload(tab, includeFaviconData = true) {
  const pageUrl = tab.url ?? null;
  const profileID = await profileIDForThisChromeProfile();

  return {
    tabID: tab.id ?? -1,
    windowID: tab.windowId ?? -1,
    profileID,
    url: pageUrl,
    title: tab.title ?? null,
    favIconURL: tab.favIconUrl ?? null,
    favIconDataURL: await faviconDataUrlOnce(pageUrl, includeFaviconData),
    active: Boolean(tab.active)
  };
}

async function profileIDForThisChromeProfile() {
  if (profileIDPromise) {
    return profileIDPromise;
  }

  profileIDPromise = loadProfileID();
  return profileIDPromise;
}

async function loadProfileID() {
  const stored = await chrome.storage.local.get(PROFILE_ID_KEY);
  if (stored[PROFILE_ID_KEY]) {
    return stored[PROFILE_ID_KEY];
  }

  const profileID = crypto.randomUUID();
  await chrome.storage.local.set({ [PROFILE_ID_KEY]: profileID });
  return profileID;
}

function profileLabel(profileID) {
  return `Chrome Profile ${profileID.slice(0, 8)}`;
}

async function ensureHeartbeat() {
  const alarm = await chrome.alarms.get(HEARTBEAT_ALARM);
  if (!alarm) {
    await chrome.alarms.create(HEARTBEAT_ALARM, { periodInMinutes: HEARTBEAT_MINUTES });
  }
}

async function openTabInventory(includeFaviconData = true) {
  const tabs = await chrome.tabs.query({});
  const activeFirst = [...tabs].sort((lhs, rhs) => Number(Boolean(rhs.active)) - Number(Boolean(lhs.active)));
  return Promise.all(activeFirst.map((tab, index) => tabPayload(tab, includeFaviconData && index < OPEN_TAB_FAVICON_DATA_LIMIT)));
}

async function activeTab() {
  const [tab] = await chrome.tabs.query({ active: true, lastFocusedWindow: true });
  return tab ?? null;
}

function eventSignature(message) {
  const openTabIDs = (message.openTabs ?? [])
    .map((tab) => `${tab.profileID ?? ""}:${tab.windowID}:${tab.tabID}:${tab.url ?? ""}:${tab.active ? "1" : "0"}`)
    .join("|");
  return [
    message.profileID,
    message.windowID,
    message.tabID,
    message.url,
    message.title,
    message.favIconURL,
    openTabIDs
  ].join("||");
}

function shouldSuppressDuplicate(type, message) {
  if (type !== "tabUpdated") return false;

  const signature = eventSignature(message);
  const now = Date.now();
  const duplicate = signature === lastSentSignature && now - lastSentAt < 3000;
  lastSentSignature = signature;
  lastSentAt = now;
  return duplicate;
}

async function sendActiveTab(type) {
  const tab = await activeTab();
  if (!tab || !isTrackablePageUrl(tab.url)) return;

  const includeFaviconData = FAVICON_EVENT_TYPES.has(type);
  const payload = await tabPayload(tab, includeFaviconData);
  const profileID = payload.profileID;
  const message = {
    type,
    profileID,
    profileName: profileLabel(profileID),
    url: payload.url,
    title: payload.title ?? "",
    domain: domainFromUrl(payload.url),
    favIconURL: payload.favIconURL,
    favIconDataURL: payload.favIconDataURL,
    tabID: payload.tabID,
    windowID: payload.windowID,
    active: true,
    capturedAt: new Date().toISOString(),
    openTabs: await openTabInventory(includeFaviconData)
  };

  if (shouldSuppressDuplicate(type, message)) return;

  const nativePort = connect();
  if (nativePort) {
    nativePort.postMessage(message);
  }
}

chrome.tabs.onActivated.addListener(() => {
  ensureHeartbeat();
  sendActiveTab("tabActivated");
});

chrome.tabs.onUpdated.addListener((tabId, changeInfo, tab) => {
  ensureHeartbeat();
  if (tab.active && (changeInfo.url || changeInfo.title || changeInfo.status === "complete")) {
    sendActiveTab("tabUpdated");
  }
});

chrome.tabs.onCreated.addListener(() => {
  ensureHeartbeat();
  sendActiveTab("tabCreated");
});

chrome.tabs.onRemoved.addListener(() => {
  ensureHeartbeat();
  sendActiveTab("tabRemoved");
});

chrome.windows.onFocusChanged.addListener((windowId) => {
  ensureHeartbeat();
  if (windowId !== chrome.windows.WINDOW_ID_NONE) {
    sendActiveTab("windowFocused");
  }
});

chrome.runtime.onStartup.addListener(() => {
  ensureHeartbeat();
  sendActiveTab("startup");
});

chrome.runtime.onInstalled.addListener(() => {
  ensureHeartbeat();
  sendActiveTab("installed");
});

chrome.alarms.onAlarm.addListener((alarm) => {
  if (alarm.name === HEARTBEAT_ALARM) {
    sendActiveTab("heartbeat");
  }
});

sendActiveTab("serviceWorkerStarted");
ensureHeartbeat().catch(() => {});
