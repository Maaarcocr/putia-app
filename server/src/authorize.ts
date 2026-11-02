import type { ConsentDescription } from "@cloudflare/workers-oauth-provider";
import { agentsKey, pairingAccount, redeemPairingCode } from "./accounts";
import type { Env, Props } from "./env";

// The sign-in page an AI opens when it connects: it shows who is asking and asks for the
// pairing code from Putia's Bench tab. The code proves the person connecting owns the account.
// In English or Italian, like the app, following the browser's first language.

const escape = (value: string) => value.replace(/[&<>"']/g, (char) => `&#${char.charCodeAt(0)};`);

const WORDS = {
  en: {
    title: (name: string) => `Connect ${name} to Putia?`,
    publishedBy: (domain: string) => `Published by <strong>${domain}</strong>.`,
    unverified: "This app registered itself; its name is not verified.",
    access: (host: string) =>
      `It will be able to see your wardrobe and its photos, propose outfits, comment, and suggest what's missing. Every change it makes is kept in your history and can be undone. Access goes to <strong>${host}</strong>.`,
    loopback: "<strong>This sends access to an app on your computer.</strong> Continue only if you just started connecting from it.",
    codeLabel: "Pairing code from Putia → Bench → Connect an AI",
    connect: "Connect",
    cancel: "Cancel",
    disconnect: "You can disconnect every AI at any time from Putia's Bench tab.",
    rejectedTitle: "That code didn't work",
    rejected: "Codes work once and expire after 10 minutes. Get a new one in Putia → Bench → Connect an AI.",
    retry: "Try again",
    cantConnect: "Can't connect",
  },
  it: {
    title: (name: string) => `Collegare ${name} a Putia?`,
    publishedBy: (domain: string) => `Pubblicata da <strong>${domain}</strong>.`,
    unverified: "Questa app si è registrata da sola: il suo nome non è verificato.",
    access: (host: string) =>
      `Potrà vedere il tuo armadio e le sue foto, proporre abbinamenti, commentare e suggerire cosa manca. Ogni sua modifica resta nella cronologia e si può annullare. L'accesso va a <strong>${host}</strong>.`,
    loopback: "<strong>L'accesso va a un'app sul tuo computer.</strong> Continua solo se hai appena iniziato il collegamento da lì.",
    codeLabel: "Codice da Putia → Banco → Collega un'IA",
    connect: "Collega",
    cancel: "Annulla",
    disconnect: "Puoi scollegare tutte le IA in qualsiasi momento dal Banco di Putia.",
    rejectedTitle: "Il codice non ha funzionato",
    rejected: "I codici valgono una volta e scadono dopo 10 minuti. Generane uno nuovo in Putia → Banco → Collega un'IA.",
    retry: "Riprova",
    cantConnect: "Impossibile collegarsi",
  },
};

type Language = keyof typeof WORDS;
const language = (request: Request): Language => (/^it\b/i.test(request.headers.get("Accept-Language") ?? "") ? "it" : "en");

function page(lang: Language, title: string, body: string, status = 200, headers = new Headers()): Response {
  headers.set("Content-Type", "text/html; charset=utf-8");
  const html = `<!doctype html>
<html lang="${lang}"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>${escape(title)}</title>
<style>
  body { font: 17px -apple-system, system-ui, sans-serif; max-width: 30rem; margin: 3rem auto; padding: 0 1rem; color: #111; }
  input { font: 24px ui-monospace, monospace; letter-spacing: .2em; text-transform: uppercase; width: 100%; padding: .5rem; box-sizing: border-box; }
  button { font: inherit; padding: .6rem 1.2rem; margin: 1rem .5rem 0 0; }
  .muted { color: #666; }
  @media (prefers-color-scheme: dark) { body { background: #000; color: #eee; } .muted { color: #999; } }
</style></head><body>${body}</body></html>`;
  return new Response(html, { status, headers });
}

function consentPage(lang: Language, details: ConsentDescription, handle: string, retry: string, headers: Headers): Response {
  const words = WORDS[lang];
  const name = escape(details.clientName);
  const origin = details.clientDomain ? words.publishedBy(escape(details.clientDomain)) : words.unverified;
  return page(
    lang,
    words.title(details.clientName),
    `<h1>${words.title(name)}</h1>
<p>${origin} ${words.access(escape(details.redirectHost))}</p>
${details.redirectIsLoopback ? `<p>${words.loopback}</p>` : ""}
<form method="post">
  <input type="hidden" name="handle" value="${escape(handle)}">
  <input type="hidden" name="retry" value="${escape(retry)}">
  <label for="code">${words.codeLabel}</label>
  <input id="code" name="code" autocomplete="one-time-code" autocapitalize="characters" required>
  <button name="decision" value="approve">${words.connect}</button>
  <button name="decision" value="deny" formnovalidate>${words.cancel}</button>
</form>
<p class="muted">${words.disconnect}</p>`,
    200,
    headers,
  );
}

function codeRejected(request: Request, retry: string): Response {
  const lang = language(request);
  const words = WORDS[lang];
  // Only offer to start over on this server's own sign-in URL.
  const sameOrigin = retry.startsWith(`${new URL(request.url).origin}/authorize?`);
  return page(
    lang,
    words.rejectedTitle,
    `<h1>${words.rejectedTitle}</h1>
<p>${words.rejected}</p>
${sameOrigin ? `<p><a href="${escape(retry)}">${words.retry}</a></p>` : ""}`,
    400,
  );
}

export async function handleAuthorize(request: Request, env: Env): Promise<Response> {
  const oauth = env.OAUTH_PROVIDER;
  if (request.method === "GET") {
    const lang = language(request);
    let authRequest: Awaited<ReturnType<typeof oauth.parseAuthRequest>>;
    try {
      authRequest = await oauth.parseAuthRequest(request);
    } catch (error) {
      // Never redirect a request whose client or redirect address didn't check out.
      const message = error instanceof Error ? error.message : "Invalid request";
      return page(lang, WORDS[lang].cantConnect, `<h1>${WORDS[lang].cantConnect}</h1><p>${escape(message)}</p>`, 400);
    }
    const details = await oauth.describeConsent(authRequest);
    const consent = await oauth.beginConsent(authRequest);
    return consentPage(lang, details, consent.handle, request.url, consent.headers);
  }

  const form = await request.formData();
  const handle = String(form.get("handle") ?? "");
  const retry = String(form.get("retry") ?? "");
  if (form.get("decision") !== "approve") {
    const denied = await oauth.denyConsent(request, handle);
    return new Response(null, { status: 302, headers: denied.headers });
  }

  const code = String(form.get("code") ?? "");
  if (!code || !(await pairingAccount(env.DB, code))) return codeRejected(request, retry);

  const approved = await oauth.approveConsent(request, handle, {});
  const { clientName } = await oauth.describeConsent(approved.request);
  // Uses the code; the app's waiting screen sees it was used, and by whom.
  const accountId = await redeemPairingCode(env.DB, code, clientName);
  const key = accountId ? await agentsKey(env.DB, accountId) : null;
  if (!accountId || !key) return codeRejected(request, retry);

  const props: Props = { accountId, agentsKey: key, agentName: clientName };
  const { redirectTo } = await oauth.completeAuthorization({
    request: approved.request,
    userId: accountId,
    metadata: {},
    scope: approved.request.scope,
    props,
  });
  approved.headers.set("Location", redirectTo);
  return new Response(null, { status: 302, headers: approved.headers });
}
