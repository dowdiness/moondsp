// Ownership for everything the workspace mounts: one place to release it all,
// newest first, so a shell is always disposed before what it depends on.

export type Disposable = { dispose(): void };

export type Scope = Disposable & {
  own<T extends Disposable>(resource: T): T;
};

export function createScope(): Scope {
  const owned: Disposable[] = [];
  return {
    own(resource) {
      owned.push(resource);
      return resource;
    },
    dispose() {
      while (owned.length) owned.pop()!.dispose();
    },
  };
}
