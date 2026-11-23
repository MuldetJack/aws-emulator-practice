#!/usr/bin/env node
//
// Genera una URL prefirmada de SUBIDA (PUT) para S3, con SigV4 a mano.
//
//   node labs/tools/presign-put.mjs <bucket> <key> [segundos]
//
// Por qué existe este archivo: `aws s3 presign` solo firma GET. Para que un
// teléfono SUBA un archivo directo a S3 hace falta firmar un PUT, y eso en la
// vida real lo hace el SDK (getSignedUrl de @aws-sdk/s3-request-presigner).
// Acá está escrito a mano, con node:crypto y nada más, para que veas qué es
// exactamente una URL prefirmada: una request firmada con la firma movida a
// la query string. No hay magia ni sesión: la firma viaja en la URL.

import { createHash, createHmac } from "node:crypto";
import { readFileSync } from "node:fs";

const [bucket, key, segundos = "300"] = process.argv.slice(2);
if (!bucket || !key) {
  console.error("uso: presign-put.mjs <bucket> <key> [segundos]");
  process.exit(2);
}

// --- credenciales: del entorno, o del archivo que escribe el emulador --------

function credenciales() {
  if (process.env.AWS_ACCESS_KEY_ID && process.env.AWS_SECRET_ACCESS_KEY) {
    return {
      id: process.env.AWS_ACCESS_KEY_ID,
      secreto: process.env.AWS_SECRET_ACCESS_KEY,
      token: process.env.AWS_SESSION_TOKEN || null,
    };
  }
  const archivo = process.env.AWS_SHARED_CREDENTIALS_FILE;
  if (!archivo) throw new Error("no hay credenciales: sourceá env.sh primero");
  const txt = readFileSync(archivo, "utf8");
  const leer = (campo) => (txt.match(new RegExp(`^${campo}\\s*=\\s*(.+)$`, "m")) || [])[1]?.trim();
  const id = leer("aws_access_key_id");
  const secreto = leer("aws_secret_access_key");
  if (!id || !secreto) throw new Error(`no pude leer credenciales de ${archivo}`);
  return { id, secreto, token: leer("aws_session_token") || null };
}

// --- SigV4 -------------------------------------------------------------------

const sha256 = (x) => createHash("sha256").update(x).digest("hex");
const hmac = (clave, dato) => createHmac("sha256", clave).update(dato).digest();

// AWS exige RFC 3986 estricto: encodeURIComponent deja sin codificar !'()*
const enc = (s) =>
  encodeURIComponent(s).replace(/[!'()*]/g, (c) => "%" + c.charCodeAt(0).toString(16).toUpperCase());

const { id, secreto, token } = credenciales();
const region = process.env.AWS_REGION || "us-east-1";
const endpoint = process.env.AWS_ENDPOINT_URL || `https://s3.${region}.amazonaws.com`;
const host = new URL(endpoint).host;

const ahora = new Date();
const amzDate = ahora.toISOString().replace(/[:-]|\.\d{3}/g, "");  // 20261121T022831Z
const fecha = amzDate.slice(0, 8);                                  // 20261121
const scope = `${fecha}/${region}/s3/aws4_request`;

// El emulador usa path-style: https://host/bucket/key
const rutaCanonica = `/${bucket}/${key.split("/").map(enc).join("/")}`;

const params = {
  "X-Amz-Algorithm": "AWS4-HMAC-SHA256",
  "X-Amz-Credential": `${id}/${scope}`,
  "X-Amz-Date": amzDate,
  "X-Amz-Expires": String(segundos),
  "X-Amz-SignedHeaders": "host",
};
if (token) params["X-Amz-Security-Token"] = token;

// La query canónica va ordenada por nombre de parámetro, siempre.
const queryCanonica = Object.keys(params).sort()
  .map((k) => `${enc(k)}=${enc(params[k])}`).join("&");

// UNSIGNED-PAYLOAD: la firma no cubre el cuerpo. Por eso el teléfono puede
// subir cualquier contenido sin que haya que firmarlo de antemano.
const requestCanonica = [
  "PUT",
  rutaCanonica,
  queryCanonica,
  `host:${host}\n`,
  "host",
  "UNSIGNED-PAYLOAD",
].join("\n");

const stringToSign = [
  "AWS4-HMAC-SHA256",
  amzDate,
  scope,
  sha256(requestCanonica),
].join("\n");

// La clave de firma se deriva en cadena: fecha -> región -> servicio -> request.
// Por eso una firma sirve solo para ese día, esa región y ese servicio.
const claveFirma = ["aws4_request"].reduce(
  (k, paso) => hmac(k, paso),
  hmac(hmac(hmac(`AWS4${secreto}`, fecha), region), "s3"),
);

const firma = createHmac("sha256", claveFirma).update(stringToSign).digest("hex");

if (process.env.PRESIGN_DEBUG) {
  console.error("--- canonical request ---\n" + requestCanonica);
  console.error("--- string to sign ---\n" + stringToSign);
}

console.log(`${endpoint}${rutaCanonica}?${queryCanonica}&X-Amz-Signature=${firma}`);
