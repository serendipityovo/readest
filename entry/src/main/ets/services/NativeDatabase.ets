import { relationalStore } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { fileIo as fs } from '@kit.CoreFileKit';

interface QueryResult { rowsAffected: number; lastInsertId: number }
interface ConfigInfo { encrypted: boolean }
interface StoreIdentity { name: string; dir: string }
interface ConvertedSql { sql: string; args: Array<relationalStore.ValueType> }
type DbRow = Record<string, Object | null>;

/**
 * tauri-plugin-turso backend on @ohos.data.relationalStore (SQLite).
 *
 * Contract (readest src-tauri/plugins/tauri-plugin-turso/guest-js/index.ts):
 * - load({options:{path:"sqlite:<abs>"}}) -> the db path string echoed back;
 *   every later command addresses the db by that exact string.
 * - execute(db, query, values) -> {rowsAffected, lastInsertId}
 * - select(db, query, values) -> array of row objects keyed by column name
 * - batch(db, [sql]) -> atomic (frontend migrate() relies on it)
 * - sync -> no-op for local-only databases; close(db?) -> boolean.
 *
 * Placeholder translation: turso binds values[i] to $i+1 / ?i+1, relationalStore
 * binds positionally, so numbered placeholders are rewritten to '?' in
 * appearance order with the values reordered to match. batch() runs inside
 * store.beginTransaction/commit (executeSql rejects BEGIN/COMMIT text, and
 * the tracking insert + PRAGMA user_version must commit atomically).
 *
 * File placement is a sanctioned substitution: relationalStore stores under
 * databaseDir/rdb/<customDir>/<name> instead of the tauri AppConfig path; the
 * frontend only ever touches the db through these commands (no fs-level db
 * copies exist in readest services, verified by grep 2026-10-15).
 */
export class NativeDatabase {
  private context: common.UIAbilityContext | null = null;
  private stores: Map<string, relationalStore.RdbStore> = new Map();

  setContext(context: common.UIAbilityContext): void {
    this.context = context;
  }

  /** plugin:turso|load — open (or create) the store, echo the path as handle. */
  async load(options: Record<string, Object>): Promise<string> {
    const path: string = options['path'] !== undefined ? String(options['path']) : '';
    const store = await this.openStore(path);
    this.stores.set(path, store);
    this.ensureMarker(path);
    return path;
  }

  /**
   * The frontend gates DB access on FILE existence (appService.databaseExists
   * = fs.exists on the sqlite: path — librarySearchService probes search.db
   * before opening). relationalStore keeps data under databaseDir/rdb, so a
   * 0-byte marker at the original path stands in for "database exists"
   * (probed in the browser lab on D3; deleteDatabase removes the marker and
   * the next load recreates it alongside a rebuilt store).
   */
  private ensureMarker(uri: string): void {
    const p: string = uri.startsWith('sqlite:') ? uri.slice('sqlite:'.length) : uri;
    if (!p.startsWith('/') || this.markerExists(p)) {
      return;
    }
    try {
      this.ensureDirFor(p);
      const f: fs.File = fs.openSync(p, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE);
      fs.closeSync(f);
    } catch (e) {
      // best-effort: searches degrade to no-index rather than crash
    }
  }

  private markerExists(p: string): boolean {
    try {
      return fs.accessSync(p);
    } catch (e) {
      return false;
    }
  }

  private ensureDirFor(p: string): void {
    const i: number = p.lastIndexOf('/');
    if (i <= 0) {
      return;
    }
    const dir: string = p.slice(0, i);
    if (this.markerExists(dir)) {
      return;
    }
    try {
      fs.mkdirSync(dir, true);
    } catch (e) {
      // created concurrently
    }
  }

  /** plugin:turso|execute — run one statement, report affected rows + rowid. */
  async execute(db: string, query: string, values: Object[]): Promise<QueryResult> {
    const store = await this.storeFor(db);
    const conv: ConvertedSql = this.convertParams(query, values);
    await store.executeSql(conv.sql, conv.args);
    if (!this.isDml(query)) {
      const none: QueryResult = { rowsAffected: 0, lastInsertId: 0 };
      return none; // DDL/PRAGMA: turso reports zeros, last_insert_rowid would be stale
    }
    const rs = await store.querySql('SELECT changes(), last_insert_rowid()');
    let rowsAffected: number = 0;
    let lastInsertId: number = 0;
    if (rs.goToNextRow()) {
      rowsAffected = Number(rs.getLong(0));
      lastInsertId = Number(rs.getLong(1));
    }
    rs.close();
    const result: QueryResult = { rowsAffected: rowsAffected, lastInsertId: lastInsertId };
    return result;
  }

  /** plugin:turso|select — rows as objects keyed by column name. */
  async select(db: string, query: string, values: Object[]): Promise<Array<DbRow>> {
    const store = await this.storeFor(db);
    const conv: ConvertedSql = this.convertParams(query, values);
    const rs = await store.querySql(conv.sql, conv.args);
    const cols: Array<string> = rs.getColumnNames();
    const rows: Array<DbRow> = [];
    while (rs.goToNextRow()) {
      const row: DbRow = {};
      for (let i = 0; i < cols.length; i++) {
        row[cols[i]] = this.columnValue(rs, i);
      }
      rows.push(row);
    }
    rs.close();
    return rows;
  }

  /** plugin:turso|batch — statements arrive pre-split; atomic via transaction. */
  async batch(db: string, queries: string[]): Promise<void> {
    const store = await this.storeFor(db);
    store.beginTransaction();
    try {
      for (let i = 0; i < queries.length; i++) {
        await store.executeSql(queries[i]);
      }
      store.commit();
    } catch (e) {
      store.rollBack();
      throw e as Error;
    }
  }

  /** plugin:turso|sync — local-only databases; contract no-op. */
  async sync(db: string): Promise<null> {
    return null;
  }

  /** plugin:turso|close — close one db by handle, or all when omitted. */
  async close(db?: string): Promise<boolean> {
    if (db !== undefined && db !== null && db.length > 0) {
      await this.closeOne(db);
      return true;
    }
    const keys: string[] = Array.from(this.stores.keys());
    for (let i = 0; i < keys.length; i++) {
      await this.closeOne(keys[i]);
    }
    return true;
  }

  /** plugin:turso|get_config — encryption is not wired (matches MVP note). */
  getConfig(): ConfigInfo {
    const result: ConfigInfo = { encrypted: false };
    return result;
  }

  // ---- internals ----

  private async closeOne(key: string): Promise<void> {
    const store: relationalStore.RdbStore | undefined = this.stores.get(key);
    if (store === undefined) {
      return;
    }
    this.stores.delete(key);
    try {
      await store.close();
    } catch (e) {
      // already closed elsewhere — the contract only asks for true
    }
  }

  private async storeFor(db: string): Promise<relationalStore.RdbStore> {
    const existing: relationalStore.RdbStore | undefined = this.stores.get(db);
    if (existing !== undefined) {
      return existing;
    }
    // not pre-loaded: open lazily so a missed load degrades instead of throwing
    const store = await this.openStore(db);
    this.stores.set(db, store);
    return store;
  }

  private async openStore(path: string): Promise<relationalStore.RdbStore> {
    if (!this.context) {
      throw new Error('no ability context for database');
    }
    const id: StoreIdentity = this.storeIdentity(path);
    const config: relationalStore.StoreConfig = {
      name: id.name,
      securityLevel: relationalStore.SecurityLevel.S1
    };
    if (id.dir.length > 0) {
      config.customDir = id.dir;
    }
    return await relationalStore.getRdbStore(this.context, config);
  }

  /**
   * Map a "sqlite:<abs path>" URI to a collision-proof rdb file identity:
   * the sandbox-relative directory is flattened into customDir, the basename
   * becomes the store name (per-book search.db files share a basename).
   */
  private storeIdentity(uri: string): StoreIdentity {
    let p: string = String(uri ?? '');
    if (p.startsWith('sqlite:')) {
      p = p.slice('sqlite:'.length);
    }
    let tag: string = 'other';
    if (this.context) {
      const filesDir: string = this.context.filesDir;
      const cacheDir: string = this.context.cacheDir;
      if (p.startsWith(filesDir)) {
        p = p.slice(filesDir.length);
        tag = 'files';
      } else if (p.startsWith(cacheDir)) {
        p = p.slice(cacheDir.length);
        tag = 'cache';
      }
    }
    const segs: string[] = p.split('/').filter((s: string) => s.length > 0);
    let name: string = segs.length > 0 ? segs[segs.length - 1] : 'default.db';
    name = name.replace(/[^A-Za-z0-9._-]/g, '_');
    if (!name.endsWith('.db')) {
      name = `${name}.db`;
    }
    const dirParts: string[] = [`turso__${tag}`];
    for (let i = 0; i < segs.length - 1; i++) {
      const seg: string = segs[i].replace(/[^A-Za-z0-9._-]/g, '_');
      if (seg.length > 0) {
        dirParts.push(seg);
      }
    }
    return { name: name, dir: dirParts.join('__') };
  }

  private isDml(query: string): boolean {
    return /^\s*(insert|replace|update|delete)\b/i.test(query);
  }

  /**
   * turso numbered placeholders ($1, ?2 -> values[N-1]) -> relationalStore
   * positional '?'. Bare '?' stays sequential. Quote-aware so '?' inside SQL
   * string literals is untouched.
   */
  private convertParams(query: string, values: Object[]): ConvertedSql {
    if (values === null || values.length === 0) {
      const unchanged: ConvertedSql = { sql: query, args: [] };
      return unchanged;
    }
    const out: string[] = [];
    const args: Array<relationalStore.ValueType> = [];
    let inString: boolean = false;
    let i: number = 0;
    while (i < query.length) {
      const ch: string = query.charAt(i);
      if (ch === "'") {
        inString = !inString;
        out.push(ch);
        i++;
        continue;
      }
      if (!inString && (ch === '$' || ch === '?')) {
        let j: number = i + 1;
        let num: string = '';
        while (j < query.length && query.charAt(j) >= '0' && query.charAt(j) <= '9') {
          num += query.charAt(j);
          j++;
        }
        const idx: number = num.length > 0 ? parseInt(num) - 1 : args.length;
        out.push('?');
        const v: Object | undefined = idx >= 0 && idx < values.length ? values[idx] : undefined;
        args.push(this.toValue(v));
        i = j;
        continue;
      }
      out.push(ch);
      i++;
    }
    const converted: ConvertedSql = { sql: out.join(''), args: args };
    return converted;
  }

  private toValue(v: Object | undefined): relationalStore.ValueType {
    if (v === null || v === undefined) {
      return null;
    }
    if (typeof v === 'number' || typeof v === 'string' || typeof v === 'boolean') {
      return v as relationalStore.ValueType;
    }
    if (v instanceof Uint8Array) {
      return v;
    }
    return JSON.stringify(v); // arrays/objects as JSON strings, mirroring serde defaults
  }

  private columnValue(rs: relationalStore.ResultSet, index: number): Object | null {
    if (rs.isColumnNull(index)) {
      return null;
    }
    const t: relationalStore.ColumnType = rs.getColumnTypeSync(index);
    if (t === relationalStore.ColumnType.TEXT) {
      return rs.getString(index);
    }
    if (t === relationalStore.ColumnType.INTEGER) {
      return rs.getLong(index);
    }
    if (t === relationalStore.ColumnType.REAL) {
      return rs.getDouble(index);
    }
    if (t === relationalStore.ColumnType.BLOB) {
      const blob: Uint8Array = rs.getBlob(index);
      const out: number[] = [];
      for (let k = 0; k < blob.length; k++) {
        out.push(blob[k]);
      }
      return out;
    }
    return rs.getString(index);
  }
}

export const nativeDatabase: NativeDatabase = new NativeDatabase();
