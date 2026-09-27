import { appleRootCertificates } from "../lib/apple-roots.mjs";

export default function health(_request, response) {
  response.setHeader("Content-Type", "application/json; charset=utf-8");
  response.setHeader("Cache-Control", "no-store");
  try {
    const trustedRootCount = appleRootCertificates().length;
    response.statusCode = 200;
    response.end(JSON.stringify({ status: "ok", service: "admission-report-proxy", trustedRootCount }));
  } catch {
    response.statusCode = 503;
    response.end(JSON.stringify({ status: "unavailable", service: "admission-report-proxy", error: "invalid_apple_roots" }));
  }
}
