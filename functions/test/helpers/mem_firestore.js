// Shared in-memory Firestore stub for AI-evaluation unit tests.
//
// FieldValue sentinels are resolved on write: serverTimestamp ->
// Timestamp.now(), delete -> field removal, any other transform
// (increment) -> numeric +1 (all re-read increments in the code under
// test are +1; metric increments are only asserted for presence).
const {Timestamp, FieldValue} = require('firebase-admin/firestore');

function resolve(current, data) {
  const out = {...(current ?? {})};
  for (const [key, value] of Object.entries(data)) {
    if (value instanceof FieldValue) {
      if (value.isEqual(FieldValue.serverTimestamp())) {
        out[key] = Timestamp.fromDate(new Date());
      } else if (value.isEqual(FieldValue.delete())) {
        delete out[key];
      } else {
        out[key] = (Number(out[key]) || 0) + 1;
      }
    } else {
      out[key] = value;
    }
  }
  return out;
}

function fieldOf(value, dottedPath) {
  return dottedPath.split('.').reduce((acc, part) => (acc ?? {})[part], value);
}

function matches(value, op, target) {
  if (op === '==') return value === target;
  const a = value instanceof Timestamp ? value.toMillis() :
    value instanceof Date ? value.getTime() : value;
  const b = target instanceof Timestamp ? target.toMillis() :
    target instanceof Date ? target.getTime() : target;
  if (a === undefined || a === null) return false;
  if (op === '<') return a < b;
  if (op === '>') return a > b;
  if (op === '<=') return a <= b;
  if (op === '>=') return a >= b;
  return false;
}

function memDb(initial = {}) {
  const store = new Map(Object.entries(initial));
  const writes = [];

  function snapOf(path) {
    const value = store.get(path);
    return {
      exists: value !== undefined,
      id: path.split('/').pop(),
      ref: {path},
      data: () => value,
    };
  }

  function docRef(path) {
    return {
      path,
      get: async () => snapOf(path),
      set: async (data, opts) => {
        const base = opts && opts.merge ? store.get(path) : undefined;
        store.set(path, resolve(base, data));
        writes.push({type: 'set', path, data});
      },
      create: async (data) => {
        if (store.has(path)) {
          const err = new Error('already exists');
          err.code = 6;
          throw err;
        }
        store.set(path, resolve(undefined, data));
        writes.push({type: 'create', path, data});
      },
    };
  }

  function queryable(matchPath) {
    const filters = [];
    let limitN = Infinity;
    const builder = {
      where: (field, op, target) => {
        filters.push({field, op, target});
        return builder;
      },
      orderBy: (field, dir) => {
        builder._orderBy = {field, dir: dir ?? 'asc'};
        return builder;
      },
      limit: (n) => {
        limitN = n;
        return builder;
      },
      get: async () => {
        let docs = [];
        for (const [path, value] of store.entries()) {
          if (!matchPath(path)) continue;
          const pass = filters.every(
            (f) => matches(fieldOf(value, f.field), f.op, f.target));
          if (pass) docs.push(snapOf(path));
        }
        if (builder._orderBy) {
          const {field, dir} = builder._orderBy;
          docs.sort((x, y) => {
            const a = fieldOf(x.data(), field);
            const b = fieldOf(y.data(), field);
            const av = a instanceof Timestamp ? a.toMillis() : a;
            const bv = b instanceof Timestamp ? b.toMillis() : b;
            return (av < bv ? -1 : av > bv ? 1 : 0) * (dir === 'desc' ? -1 : 1);
          });
        }
        docs = docs.slice(0, limitN === Infinity ? undefined : limitN);
        return {docs, size: docs.length};
      },
    };
    return builder;
  }

  const db = {
    doc: (path) => docRef(path),
    collection: (colPath) => queryable((path) =>
      path.startsWith(`${colPath}/`) &&
      !path.slice(colPath.length + 1).includes('/')),
    collectionGroup: (name) => queryable((path) => {
      const parts = path.split('/');
      return parts.length >= 2 && parts[parts.length - 2] === name;
    }),
    batch: () => {
      const ops = [];
      return {
        set: (ref, data, opts) => ops.push({kind: 'set', ref, data, opts}),
        update: (ref, data) => ops.push({kind: 'update', ref, data}),
        delete: (ref) => ops.push({kind: 'delete', ref}),
        commit: async () => {
          for (const op of ops) {
            if (op.kind === 'delete') {
              store.delete(op.ref.path);
              writes.push({type: 'delete', path: op.ref.path});
            } else if (op.kind === 'set') {
              const base =
                op.opts && op.opts.merge ? store.get(op.ref.path) : undefined;
              store.set(op.ref.path, resolve(base, op.data));
              writes.push({type: 'set', path: op.ref.path, data: op.data});
            } else {
              store.set(op.ref.path, resolve(store.get(op.ref.path), op.data));
              writes.push({type: 'update', path: op.ref.path, data: op.data});
            }
          }
        },
      };
    },
    runTransaction: async (fn) => fn({
      get: async (ref) => snapOf(ref.path),
      set: (ref, data) => {
        store.set(ref.path, resolve(undefined, data));
        writes.push({type: 'txSet', path: ref.path, data});
      },
      update: (ref, data) => {
        if (!store.has(ref.path)) throw new Error(`missing doc ${ref.path}`);
        store.set(ref.path, resolve(store.get(ref.path), data));
        writes.push({type: 'txUpdate', path: ref.path, data});
      },
      create: (ref, data) => {
        store.set(ref.path, resolve(undefined, data));
        writes.push({type: 'txCreate', path: ref.path, data});
      },
    }),
  };
  return {db, store, writes};
}

module.exports = {memDb};
