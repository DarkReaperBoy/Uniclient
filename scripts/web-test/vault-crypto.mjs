// Vault decryption helper for the E2E suite: the web vault is localStorage
// JSON {version, salt, ciphertext} — Argon2id(password, salt) → AES-256-GCM
// (nonce prepended), exactly as utils/vault.go + utils/crypto.go define it.
// Lets the tests count accounts in the persisted vault instead of guessing
// from ciphertext sizes.
import { argon2id } from "hash-wasm";
import { createDecipheriv } from "node:crypto";

export async function decryptVault(vaultJsonStr, password = "uniclient") {
  const vf = JSON.parse(vaultJsonStr);
  const salt = Buffer.from(vf.salt, "base64");
  const key = await argon2id({
    password,
    salt,
    parallelism: 4,
    iterations: 3,
    memorySize: 65536,
    hashLength: 32,
    outputType: "binary",
  });
  const raw = Buffer.from(vf.ciphertext, "base64");
  const nonce = raw.subarray(0, 12);
  const body = raw.subarray(12);
  const decipher = createDecipheriv("aes-256-gcm", Buffer.from(key), nonce);
  const tag = body.subarray(body.length - 16);
  decipher.setAuthTag(tag);
  const plain = Buffer.concat([decipher.update(body.subarray(0, body.length - 16)), decipher.final()]);
  return JSON.parse(plain.toString("utf8"));
}

export function accountCount(vaultData) {
  if (!vaultData || !vaultData.__accounts) return 0;
  return Object.keys(vaultData.__accounts).length;
}
