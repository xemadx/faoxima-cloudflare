export function publicUrl(value) {
  const url = new URL(value);
  if (url.protocol !== "https:" || url.username || url.password || url.port ||
      url.search || url.hash || !/^\/[a-zA-Z0-9_-]+\/?$/.test(url.pathname)) {
    throw new Error("PUBLIC_URL must be an HTTPS URL with one installation path segment.");
  }
  url.pathname = url.pathname.replace(/\/$/, "");
  return url;
}
