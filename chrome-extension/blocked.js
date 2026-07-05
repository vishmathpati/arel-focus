const params = new URLSearchParams(location.search);
const domain = params.get("domain") || "";
const target = params.get("target") || "";
const profile = params.get("profile") || "";
const session = params.get("session") || "";

function setText(id, value, fallback) {
  const el = document.getElementById(id);
  if (el) el.textContent = value && value.trim() ? value : fallback;
}

setText("target", target, "your work");
setText("domain", domain, "This site");
setText("profile", profile, "focus");
setText("allow-domain", domain, "this site");

const backButton = document.getElementById("back");
const allowButton = document.getElementById("allow");
const status = document.getElementById("status");

backButton.addEventListener("click", () => {
  if (history.length > 1) {
    history.back();
  } else {
    // No prior entry (the redirect replaced it) — go somewhere calm.
    location.replace("about:blank");
  }
});

allowButton.addEventListener("click", () => {
  if (!domain) return;
  allowButton.disabled = true;
  status.textContent = "Allowing " + domain + " for this session…";

  chrome.runtime.sendMessage(
    { type: "focusAllowDomain", domain, session },
    (response) => {
      if (chrome.runtime.lastError || !response?.ok) {
        allowButton.disabled = false;
        status.textContent = "Couldn't reach Arel Focus. Try again.";
        return;
      }
      status.textContent = "Allowed. Reloading…";
      // The service worker already removed this domain's block rule before it
      // replied (and keeps it allowed for the rest of the session), so the retry
      // navigation lands on the real site. A short beat lets the rule change
      // settle in Chrome before we navigate.
      setTimeout(() => {
        if (domain) {
          location.replace("https://" + domain + "/");
        } else {
          history.back();
        }
      }, 350);
    }
  );
});
