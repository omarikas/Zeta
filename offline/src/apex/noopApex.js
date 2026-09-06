// Fallback for any Apex method with no offline stub. Dual-mode so it is safe for
// both imperative calls (resolves null) and `@wire` (emits an error → consumers
// fall back to their offline/cached branch). See _wireAdapter.js.
export { default } from './_wireAdapter.js';
