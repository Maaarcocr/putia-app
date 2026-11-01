import { ATTRIBUTE_KEYS, type Data, type Kind } from "./schema";

// Who may do what. The person is "human" (the app); an AI is "agent:<connector name>".
// These rules are what keeps the AI a collaborator rather than the owner of the records:
// it suggests, proposes and comments, and the person confirms, tries and decides.

export type Actor = string;
export const HUMAN: Actor = "human";
export const isAgent = (actor: Actor): boolean => actor.startsWith("agent:");

/** A write the actor isn't allowed to make. The message says what to do instead. */
export class RuleError extends Error {}

const sameValue = (a: unknown, b: unknown) => JSON.stringify(a) === JSON.stringify(b);

type Attr = { value: unknown; state: string; by: string };
type Attrs = Record<string, Attr | undefined>;

/**
 * Applies the actor's permissions to a write. `before` is the current data (null on create);
 * `incoming` is the full proposed data. Returns the data to store.
 */
export function applyRules(kind: Kind, actor: Actor, before: Data | null, incoming: Data): Data {
  return isAgent(actor) ? agentRules(kind, actor, before, incoming) : humanRules(kind, before, incoming);
}

function humanRules(kind: Kind, before: Data | null, incoming: Data): Data {
  const data = { ...incoming };
  if (kind === "piece") {
    // Values the person changes are theirs, whoever set them before.
    const old = (before?.attrs ?? {}) as Attrs;
    const attrs: Attrs = {};
    for (const [key, attr] of Object.entries((incoming.attrs ?? {}) as Attrs)) {
      if (!attr) continue;
      const previous = old[key];
      attrs[key] = previous && sameValue(previous.value, attr.value) ? { ...attr, by: previous.by } : { ...attr, by: HUMAN };
    }
    data.attrs = attrs;
  }
  if (kind === "comment") {
    if (before) throw new RuleError("Comments can't be edited. Delete it and write a new one.");
    data.by = HUMAN;
  }
  if (kind === "review" && before) throw new RuleError("Reviews can't be edited. Delete it and record a new one.");
  return data;
}

function agentRules(kind: Kind, actor: Actor, before: Data | null, incoming: Data): Data {
  const data = { ...incoming };
  switch (kind) {
    case "piece": {
      const old = (before?.attrs ?? {}) as Attrs;
      const attrs: Attrs = {};
      for (const key of ATTRIBUTE_KEYS) {
        const next = ((incoming.attrs ?? {}) as Attrs)[key];
        const previous = old[key];
        if (!next) {
          if (previous?.state === "confirmed") attrs[key] = previous;
          continue;
        }
        if (previous && sameValue(previous.value, next.value)) {
          attrs[key] = previous;
        } else if (previous?.state === "confirmed") {
          throw new RuleError(`"${key}" was confirmed by the user. Leave a comment on the piece instead of changing it.`);
        } else {
          attrs[key] = { value: next.value, state: "suggested", by: actor };
        }
      }
      data.attrs = attrs;
      // Photos, measured colours, notes and status come from the person.
      data.swatches = before?.swatches ?? [];
      data.notes = before?.notes ?? [];
      data.photoIds = before?.photoIds ?? [];
      data.status = before?.status ?? "owned";
      if (before?.heroPhotoId !== undefined) data.heroPhotoId = before.heroPhotoId;
      else delete data.heroPhotoId;
      if (before && before.name && before.name !== incoming.name) {
        throw new RuleError("The person named this piece. Leave a comment instead of renaming it.");
      }
      return data;
    }
    case "outfit": {
      if (!before && incoming.stage !== "proposed") {
        throw new RuleError('Agents save outfits as "proposed". Only the person can mark one tried or favourite.');
      }
      if (before && before.stage !== incoming.stage) {
        throw new RuleError("Only the person can change an outfit's stage: they know whether it was worn.");
      }
      data.photoIds = before?.photoIds ?? [];
      data.wornOn = before?.wornOn ?? [];
      return data;
    }
    case "photo": {
      // The person's photos come from the app. An AI may add a photo of a piece's product that it
      // found online, saved with where it found it.
      if (before) throw new RuleError("Photos can't be changed. Delete the one you added and add another.");
      if (incoming.ownerKind !== "piece" || incoming.role !== "flat" || !incoming.source) {
        throw new RuleError("Only the person adds their own photos. You can add a product photo you found online with add_product_photo.");
      }
      return { ...data, hasCutout: false };
    }
    case "comment": {
      if (before) throw new RuleError("Comments can't be edited. Delete it and write a new one.");
      data.by = actor;
      return data;
    }
    case "reference": {
      if (!before) throw new RuleError("Inspiration images come from the person. You can add a translation to one they saved.");
      // Only the translation is the agent's to write.
      const kept = { ...before };
      if (incoming.translation === undefined) delete kept.translation;
      else kept.translation = incoming.translation;
      return kept;
    }
    case "wish": {
      if (incoming.status === "dismissed" || incoming.status === "bought") {
        throw new RuleError("Only the person can dismiss a shortlist entry or mark it bought.");
      }
      if (before && (before.status === "dismissed" || before.status === "bought") && before.status !== incoming.status) {
        throw new RuleError("The person already decided on this entry.");
      }
      return data;
    }
    case "review": {
      if (before) throw new RuleError("Reviews can't be edited. Record a new one.");
      return data;
    }
  }
}

/** Whether `actor` may delete a record that `createdBy` made. */
export function mayDelete(actor: Actor, createdBy: Actor): boolean {
  return !isAgent(actor) || createdBy === actor;
}

/** Whether `actor` may undo a change that `changeActor` made. */
export function mayUndo(actor: Actor, changeActor: Actor): boolean {
  return !isAgent(actor) || isAgent(changeActor);
}
