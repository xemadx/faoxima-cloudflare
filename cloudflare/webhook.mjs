import { createHash } from "node:crypto";
import { publicUrl } from "./settings.mjs";

async function main() {
  const { TELEGRAM_BOT_TOKEN: token, TELEGRAM_WEBHOOK_SECRET: override, PUBLIC_URL: url } = process.env;
  if (!/^\d+:[a-zA-Z0-9_-]{20,}$/.test(token ?? "")) throw new Error("Set TELEGRAM_BOT_TOKEN first.");
  const base = publicUrl(url).href;
  const secret = override || createHash("sha256").update(`${token}_faoxima_webhook_secret`).digest("hex");
  if (!/^[a-zA-Z0-9_-]{1,256}$/.test(secret)) throw new Error("Invalid TELEGRAM_WEBHOOK_SECRET.");

  async function telegram(method, payload) {
    let response;
    let body;
    try {
      response = await fetch(`https://api.telegram.org/bot${token}/${method}`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(payload),
        signal: AbortSignal.timeout(15_000),
      });
      body = await response.json();
    } catch {
      throw new Error(`Could not reach Telegram for ${method}.`);
    }
    if (!response.ok || !body.ok) throw new Error(`Telegram rejected ${method} (HTTP ${response.status}).`);
    return body.result;
  }

  const expected = `${base}/index.php`;
  if (!process.argv.includes("--verify")) {
    const health = await fetch(`${base}/app/`, { signal: AbortSignal.timeout(120_000), redirect: "error" });
    await health.body?.cancel();
    if (!health.ok) throw new Error(`The deployed Mini App is unavailable (HTTP ${health.status}).`);
    await telegram("setWebhook", { url: expected, secret_token: secret, drop_pending_updates: false });
    await telegram("setChatMenuButton", { menu_button: { type: "web_app", text: "فروشگاه", web_app: { url: `${base}/app/` } } });
  }
  const info = await telegram("getWebhookInfo", {});
  if (info.url !== expected) throw new Error("The bot webhook does not match PUBLIC_URL.");
  console.log(`Webhook verified at ${expected}. Telegram pending updates: ${info.pending_update_count}.`);
}

main().catch((error) => {
  console.error(error.message);
  process.exitCode = 1;
});
