import { X509Certificate } from "node:crypto";

const pemCertificatePattern = /-----BEGIN CERTIFICATE-----[\s\S]*?-----END CERTIFICATE-----/g;

export function appleRootCertificates() {
  const encodedBundle = process.env.APPLE_ROOT_CERTIFICATES_BASE64?.trim();
  const pemBundle = encodedBundle
    ? Buffer.from(encodedBundle, "base64").toString("utf8")
    : process.env.APPLE_ROOT_CERTIFICATES_PEM || "";
  const certificates = pemBundle.match(pemCertificatePattern) || [];

  if (!certificates.length || pemBundle.replace(pemCertificatePattern, "").trim()) {
    throw new Error("Apple root certificate bundle is missing or malformed");
  }

  return certificates.map((pem) => new X509Certificate(pem).raw);
}
