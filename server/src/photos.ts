import type { Env } from "./env";
import { type Actor, type Doc, Invalid, type Store } from "./store";

// Photos: a photo record and its two images are saved together, here, for the app and for AI.
// The server never keeps the bytes it was sent: it decodes each image and saves its own WebP copy,
// at most FULL_SIDE (or THUMB_SIDE) pixels on its long side. So what's stored is always a picture
// of a known size, and the account's photo limit (schema.ts) bounds how much an account can keep.

/** The most bytes read for one image that the server was sent or downloads. */
export const MAX_IMAGE_BYTES = 8_000_000;
const FULL_SIDE = 2000;
const THUMB_SIDE = 600;
const READABLE = ["image/jpeg", "image/png", "image/webp"];

export const photoKey = (accountId: string, photoId: string, size: "full" | "thumb") => `${accountId}/${photoId}/${size}`;

export interface NewPhoto {
  id: string;
  actor: Actor;
  /** The photo record's data: who it belongs to. */
  data: unknown;
  note?: string;
  full: ArrayBuffer;
  /** The thumbnail (the app's cut-out); made from `full` when there's none. */
  thumb?: ArrayBuffer;
}

export async function addPhoto(env: Env, store: Store, photo: NewPhoto): Promise<{ doc: Doc; seq: number }> {
  const full = await reencode(env, photo.full, FULL_SIDE);
  const thumb = await reencode(env, photo.thumb ?? photo.full, THUMB_SIDE);
  const keys = { full: photoKey(store.accountId, photo.id, "full"), thumb: photoKey(store.accountId, photo.id, "thumb") };
  // The images go first, so the record never points at images that aren't there yet.
  await env.PHOTOS.put(keys.full, full, { httpMetadata: { contentType: "image/webp" } });
  await env.PHOTOS.put(keys.thumb, thumb, { httpMetadata: { contentType: "image/webp" } });
  try {
    return await store.write({ kind: "photo", id: photo.id, actor: photo.actor, baseRevision: 0, data: photo.data, note: photo.note });
  } catch (error) {
    await env.PHOTOS.delete([keys.full, keys.thumb]);
    throw error;
  }
}

/** The server's own WebP copy of an image, scaled down to fit `side`. */
async function reencode(env: Env, bytes: ArrayBuffer, side: number): Promise<ArrayBuffer> {
  if (bytes.byteLength > MAX_IMAGE_BYTES) throw new Invalid(["The image is larger than 8 MB. Choose a smaller one."]);
  const stream = () => new Blob([bytes]).stream();
  const info = await env.IMAGES.info(stream()).catch(() => null);
  if (!info || !READABLE.includes(info.format)) throw new Invalid(["The image must be a JPEG, PNG or WebP."]);
  const result = await env.IMAGES.input(stream())
    .transform({ width: side, height: side, fit: "scale-down" })
    .output({ format: "image/webp", quality: 85 });
  return new Response(result.image()).arrayBuffer();
}

/** Reads a body, giving up past `max` bytes. Null when it's larger. */
export async function readAtMost(body: ReadableStream<Uint8Array> | null, max: number): Promise<ArrayBuffer | null> {
  if (!body) return new ArrayBuffer(0);
  const chunks: Uint8Array[] = [];
  let length = 0;
  // Leaving the loop early cancels the stream.
  for await (const chunk of body) {
    length += chunk.byteLength;
    if (length > max) return null;
    chunks.push(chunk);
  }
  return new Blob(chunks).arrayBuffer();
}
