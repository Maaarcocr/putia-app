import { ATTRIBUTE_KEYS, type Data, type Kind } from "./schema";

// Who may do what. The person is "human" (the app); an AI is "agent:<connector name>".
// These rules are what keeps the AI a collaborator rather than the owner of the records:
// it suggests, proposes and comments, and the person confirms, tries and decides.

export type Actor = string;
export const HUMAN: Actor = "human";
export const isAgent = (actor: Actor): boolean => actor.startsWith("agent:");

/** A write the actor isn't allowed to make. The message says what to do instead. */
export class RuleError extends Error {}

type Attrs = Record<string, { value: string; state: string; by: string } | undefined>;

/**
 * Applies the actor's permissions to a write. `before` is the current data (null on create);
 * `incoming` is the full proposed data. Returns the data to store.
 */
export function applyRules(kind: Kind, actor: Actor, before: Data | null, incoming: Data): Data {
  if ((kind === "comment" || kind === "review" || kind === "photo") && before) {
    throw new RuleError(`A ${kind} can't be changed. Delete it and add a new one.`);
  }
  return isAgent(actor) ? agentRules(kind, actor, before, incoming) : humanRules(kind, before, incoming);
}

function humanRules(kind: Kind, before: Data | null, incoming: Data): Data {
  if (kind !== "piece") return incoming;
  // Tags the person changes are theirs, whoever set them before.
  const old = (before?.attrs ?? {}) as Attrs;
  const attrs: Attrs = {};
  for (const [key, attr] of Object.entries(incoming.attrs as Attrs)) {
    if (attr) attrs[key] = old[key]?.value === attr.value ? { ...attr, by: old[key]!.by } : { ...attr, by: HUMAN };
  }
  return { ...incoming, attrs };
}

function agentRules(kind: Kind, actor: Actor, before: Data | null, incoming: Data): Data {
  switch (kind) {
    case "piece": {
      if (before && before.name && before.name !== incoming.name) {
        throw new RuleError("The person named this piece. Leave a comment instead of renaming it.");
      }
      // Every tag an AI sets is a suggestion; the person's confirmed tags stay as they are.
      const old = (before?.attrs ?? {}) as Attrs;
      const next = incoming.attrs as Attrs;
      const attrs: Attrs = {};
      for (const key of ATTRIBUTE_KEYS) {
        const previous = old[key];
        if (previous?.state === "confirmed") {
          if (next[key] && next[key].value !== previous.value) {
            throw new RuleError(`"${key}" was confirmed by the person. Leave a comment on the piece instead of changing it.`);
          }
          attrs[key] = previous;
        } else if (next[key]) {
          attrs[key] = previous?.value === next[key].value ? previous : { value: next[key].value, state: "suggested", by: actor };
        }
      }
      // The main photo is the person's choice.
      const { mainPhotoId: _, ...rest } = incoming;
      return before?.mainPhotoId ? { ...rest, attrs, mainPhotoId: before.mainPhotoId } : { ...rest, attrs };
    }
    case "outfit":
      if ((before?.stage ?? "proposed") !== incoming.stage) {
        throw new RuleError('Only the person marks an outfit tried or favourite. Save it as "proposed".');
      }
      return incoming;
    case "photo":
      if (incoming.ownerKind !== "piece") throw new RuleError("You can add photos to pieces only, with add_photo.");
      return incoming;
    case "reference":
      throw new RuleError("Inspiration images are the person's. Comment on one instead.");
    case "wish":
      if (incoming.status !== "considering" || (before && before.status !== "considering")) {
        throw new RuleError("Only the person marks a shortlist entry bought or dismissed.");
      }
      return incoming;
    default:
      return incoming;
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
