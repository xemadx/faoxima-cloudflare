import { DurableObject } from "cloudflare:workers";
import { publicUrl } from "./settings.mjs";

const WEB_PORT = 8080;
const CRON_PORT = 8081;
const INSTANCE = "faoxima";
const REQUIRED = [
  "DB_HOST", "DB_NAME", "DB_USER", "DB_PASS", "FILES_DB_NAME",
  "TELEGRAM_BOT_TOKEN", "TELEGRAM_ADMIN_ID", "TELEGRAM_BOT_USERNAME",
];
const OPTIONAL = [
  "DB_PORT", "DB_TLS", "DB_CA_PEM", "TELEGRAM_WEBHOOK_SECRET",
  "REDIS_HOST", "REDIS_PORT", "REDIS_PASSWORD", "REDIS_DATABASE",
];

function containerEnv(env) {
  const result = { PUBLIC_URL: publicUrl(env.PUBLIC_URL).href };
  for (const key of REQUIRED) {
    if (!env[key]) throw new Error(`Missing Faoxima setting ${key}`);
    result[key] = env[key];
  }
  for (const key of OPTIONAL) {
    if (env[key]) result[key] = env[key];
  }
  return result;
}

export class FaoximaContainer extends DurableObject {
  starting;

  async ready() {
    this.starting ??= this.startAndProbe().finally(() => { this.starting = undefined; });
    await this.starting;
  }

  async startAndProbe() {
    const container = this.ctx.container;
    if (!container.running) {
      container.start({ enableInternet: true, env: containerEnv(this.env) });
      this.ctx.waitUntil(container.monitor().catch(() => console.error("Faoxima container exited with an error")));
    }
    const port = container.getTcpPort(CRON_PORT);
    for (let attempt = 0; attempt < 120; attempt++) {
      try {
        const response = await port.fetch("http://container/health", { signal: AbortSignal.timeout(1000) });
        await response.body?.cancel();
        if (response.ok) return;
      } catch {
        // Nginx opens the private listener after initialization finishes.
      }
      if (!container.running) break;
      await new Promise((resolve) => setTimeout(resolve, 1000));
    }
    throw new Error("Faoxima container did not become ready");
  }

  async fetch(request) {
    await this.ready();
    const target = new URL(request.url);
    target.protocol = "http:";
    target.host = "container";
    const forwarded = new Request(target, request);
    const canonical = publicUrl(this.env.PUBLIC_URL);
    forwarded.headers.delete("Host");
    forwarded.headers.delete("Forwarded");
    forwarded.headers.delete("X-Forwarded-For");
    forwarded.headers.set("X-Forwarded-Host", canonical.host);
    forwarded.headers.set("X-Forwarded-Proto", "https");
    return this.ctx.container.getTcpPort(WEB_PORT).fetch(forwarded, { redirect: "manual" });
  }

  async runCron() {
    await this.ready();
    const response = await this.ctx.container.getTcpPort(CRON_PORT).fetch("http://container/cron", {
      signal: AbortSignal.timeout(90_000),
    });
    const result = (await response.text()).trim();
    if (!response.ok || !/^(OK |BUSY$)/m.test(result)) {
      throw new Error("Faoxima cron dispatcher failed");
    }
  }
}

export default {
  async fetch(request, env) {
    try {
      const canonical = publicUrl(env.PUBLIC_URL);
      const path = new URL(request.url).pathname;
      if (path === "/" || path === canonical.pathname) {
        return Response.redirect(`${canonical.href}/app/`, 308);
      }
      if (!path.startsWith(`${canonical.pathname}/`)) {
        return new Response("Not found", { status: 404 });
      }
      return await env.FAOXIMA.getByName(INSTANCE).fetch(request);
    } catch (error) {
      console.error(error instanceof Error ? error.message : "Faoxima request failed");
      return new Response("Faoxima is temporarily unavailable", { status: 503, headers: { "Retry-After": "15" } });
    }
  },

  async scheduled(_controller, env) {
    await env.FAOXIMA.getByName(INSTANCE).runCron();
  },
};
