import { Conflict, Invalid, NotFound } from "./store";

/** How a store error is reported, to the app (status + JSON) and to agents (the same JSON as text). */
export function describeError(error: unknown): { status: number; body: Record<string, unknown> } {
  if (error instanceof Conflict) return { status: 409, body: { error: error.message, current: error.current } };
  if (error instanceof Invalid) return { status: 422, body: { error: "Not saved", problems: error.problems } };
  if (error instanceof NotFound) return { status: 404, body: { error: error.message } };
  throw error;
}
