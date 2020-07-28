import { ObservedStateJSON } from "../queries";

const registeredObservers: Map<string, Promise<ObservedStateJSON>> =
  // @ts-ignore
  window.registeredObservers || emptyMap();

// @ts-ignore
const [id, done] = args;

(
  registeredObservers.get(id) ||
  Promise.reject(`No registered state observer for ID: ${id}`)
)
  .then((x) => ({
    Right: x,
  }))
  .catch((e) => ({
    Left: e,
  }))
  .then(done);
