import { common } from '@kit.AbilityKit';
import { fileIo as fs } from '@kit.CoreFileKit';

/**
 * Serves the packaged readest static frontend from filesDir/frontend over the
 * virtual host http://readest.local (so the build's absolute /_next/... paths
 * resolve), sandbox files over http://readest.ohos.internal, and byte-range
 * reads over http://rangefile.localhost (the query-range protocol the Android
 * reader path uses — Chromium re-applies Range headers on intercepted
 * responses, so the range rides in the URL query instead; lab-verified D3).
 *
 * Rawfile content is extracted to filesDir only when the packaged buildstamp
 * differs from the local one: launches after the first are fast, content
 * updates force a re-extract, and an interrupted extraction self-heals (the
 * stamp is written only after every file has landed).
 */
const FRONTEND_HOST: string = 'readest.local';
const BOOKS_HOST: string = 'readest.ohos.internal';
const RANGE_HOST: string = 'rangefile.localhost';
const STAMP_NAME: string = 'buildstamp.txt';

export class RawFileServer {
  private rootDir: string = '';
  private filesRoot: string = '';
  private cacheRoot: string = '';
  private context: common.UIAbilityContext | null = null;

  constructor(context: common.UIAbilityContext) {
    this.context = context;
    this.rootDir = `${context.filesDir}/frontend`;
    // the frontend manages its own layout under filesDir (Books live at
    // filesDir/Readest/Books — observed in the browser lab, D3); serving the
    // whole filesDir keeps book/covers/config paths uniform
    this.filesRoot = context.filesDir;
    this.cacheRoot = context.cacheDir;
  }

  async extractIfNeeded(onProgress: (done: number, total: number) => void): Promise<void> {
    if (!this.context) {
      return;
    }
    const rawStamp: string = await this.readRawStamp();
    if (rawStamp !== '' && rawStamp === this.readLocalStamp()) {
      return; // same build already extracted, skip entirely
    }
    const total: number = await this.countFiles('frontend');
    if (total === 0) {
      return;
    }
    let done: number = 0;
    await this.extractDir('frontend', (): void => {
      done += 1;
      onProgress(done, total);
    });
    this.writeLocalStamp(rawStamp);
  }

  handle(request: WebResourceRequest): WebResourceResponse {
    const response: WebResourceResponse = new WebResourceResponse();
    const url: string = request.getRequestUrl();
    const match: RegExpMatchArray | null = url.match(/^https?:\/\/([^/]+)([^?#]*)/);
    let host: string = '';
    let path: string = '/';
    if (match) {
      host = match[1];
      if (match[2]) {
        path = decodeURIComponent(match[2]);
      }
    }
    if (path === '/' || path === '') {
      path = '/index.html';
    }
    // asset-protocol style (covers etc): /asset/<url-encoded absolute path>
    if (host === BOOKS_HOST && path.startsWith('/asset/')) {
      path = path.slice('/asset/'.length); // remainder is the decoded abs path
      if (path !== '' && !path.startsWith('/')) {
        path = `/${path}`;
      }
    }
    // decoded path must never climb out of the sandbox roots
    if (path.includes('..')) {
      response.setResponseCode(403);
      response.setReasonMessage('Forbidden');
      response.setResponseData('forbidden');
      return response;
    }
    const isBooks: boolean = host === BOOKS_HOST;
    if (host === RANGE_HOST) {
      return this.handleRangeFile(url, response);
    }
    const root: string = isBooks ? this.filesRoot : this.rootDir;

    response.setResponseHeader([
      { headerKey: 'Content-Type', headerValue: this.mimeOf(path) },
      { headerKey: 'Access-Control-Allow-Origin', headerValue: '*' }
    ]);
    response.setResponseEncoding('utf-8');
    response.setResponseCode(200);
    response.setReasonMessage('OK');

    const filePath: string = `${root}${path}`;
    const data: ArrayBuffer | null = this.readSync(filePath);
    if (data !== null) {
      response.setResponseData(data);
      return response;
    }
    // SPA fallback: unknown extension-less routes resolve to the flat Next
    // export shell (<route>.html sibling — root shell renders blank at deep
    // routes, lab-verified D3), then the root index.
    if (!isBooks && !path.startsWith('/_next') && !path.includes('.')) {
      const shellData: ArrayBuffer | null = this.readSync(`${this.rootDir}${path}.html`);
      if (shellData !== null) {
        response.setResponseHeader([
          { headerKey: 'Content-Type', headerValue: 'text/html' },
          { headerKey: 'Access-Control-Allow-Origin', headerValue: '*' }
        ]);
        response.setResponseData(shellData);
        return response;
      }
      const indexData: ArrayBuffer | null = this.readSync(`${this.rootDir}/index.html`);
      if (indexData !== null) {
        response.setResponseHeader([
          { headerKey: 'Content-Type', headerValue: 'text/html' },
          { headerKey: 'Access-Control-Allow-Origin', headerValue: '*' }
        ]);
        response.setResponseData(indexData);
        return response;
      }
    }
    response.setResponseCode(404);
    response.setReasonMessage('Not Found');
    response.setResponseData('not found');
    return response;
  }

  /**
   * Query-range protocol: /?path=<abs>&start=<s>&end=<e> (inclusive) answers
   * the byte slice with the total size in X-Total-Size. Paths must stay in
   * the sandbox (filesDir/cacheDir subtree).
   */
  private handleRangeFile(url: string, response: WebResourceResponse): WebResourceResponse {
    const qIdx: number = url.indexOf('?');
    const query: string = qIdx >= 0 ? url.slice(qIdx + 1) : '';
    let p: string = '';
    let start: number = 0;
    let end: number = -1;
    const parts: string[] = query.split('&');
    for (let i = 0; i < parts.length; i++) {
      const eq: number = parts[i].indexOf('=');
      if (eq < 0) {
        continue;
      }
      const key: string = parts[i].slice(0, eq);
      const value: string = decodeURIComponent(parts[i].slice(eq + 1));
      if (key === 'path') {
        p = value;
      } else if (key === 'start') {
        start = parseInt(value) || 0;
      } else if (key === 'end') {
        end = parseInt(value) || 0;
      }
    }
    const allowedRoot: boolean = this.filesRoot.length > 0 && p.startsWith(this.filesRoot)
      || this.cacheRoot.length > 0 && p.startsWith(this.cacheRoot);
    if (!p || p.includes('..') || !allowedRoot) {
      response.setResponseCode(403);
      response.setReasonMessage('Forbidden');
      response.setResponseData('forbidden');
      return response;
    }
    const data: ArrayBuffer | null = this.readSync(p);
    if (data === null) {
      response.setResponseCode(404);
      response.setReasonMessage('Not Found');
      response.setResponseData('not found');
      return response;
    }
    const total: number = data.byteLength;
    if (end < 0 || end >= total) {
      end = total - 1;
    }
    if (end < start) {
      end = start;
    }
    const view: Uint8Array = new Uint8Array(data).subarray(start, end + 1);
    const slice: ArrayBuffer = new ArrayBuffer(view.byteLength);
    new Uint8Array(slice).set(view);
    response.setResponseCode(200);
    response.setReasonMessage('OK');
    response.setResponseHeader([
      { headerKey: 'Content-Type', headerValue: this.mimeOf(p) },
      { headerKey: 'X-Total-Size', headerValue: String(total) },
      { headerKey: 'Access-Control-Allow-Origin', headerValue: '*' }
    ]);
    response.setResponseData(slice);
    return response;
  }

  private async readRawStamp(): Promise<string> {
    try {
      const bytes: Uint8Array = await this.context!.resourceManager.getRawFileContent(`frontend/${STAMP_NAME}`);
      return this.bytesToAscii(bytes);
    } catch (e) {
      return '';
    }
  }

  private readLocalStamp(): string {
    const data: ArrayBuffer | null = this.readSync(`${this.rootDir}/${STAMP_NAME}`);
    if (data === null) {
      return '';
    }
    return this.bytesToAscii(new Uint8Array(data));
  }

  private writeLocalStamp(stamp: string): void {
    try {
      const file = fs.openSync(`${this.rootDir}/${STAMP_NAME}`,
        fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
      try {
        fs.writeSync(file.fd, stamp);
      } finally {
        fs.closeSync(file);
      }
    } catch (e) {
      console.error(`[ReadestOhos] write stamp failed: ${JSON.stringify(e)}`);
    }
  }

  private bytesToAscii(bytes: Uint8Array): string {
    let s: string = '';
    for (let i = 0; i < bytes.length; i++) {
      s += String.fromCharCode(bytes[i]);
    }
    return s.trim();
  }

  private async countFiles(rawDir: string): Promise<number> {
    let count: number = 0;
    const entries: Array<string> = await this.context!.resourceManager.getRawFileList(rawDir);
    for (let i = 0; i < entries.length; i++) {
      const rawPath: string = `${rawDir}/${entries[i]}`;
      if (await this.isRawDir(rawPath)) {
        count += await this.countFiles(rawPath);
      } else {
        count += 1;
      }
    }
    return count;
  }

  private async extractDir(rawDir: string, onFile: () => void): Promise<void> {
    const targetDir: string = `${this.context!.filesDir}/${rawDir}`;
    if (!fs.accessSync(targetDir)) {
      fs.mkdirSync(targetDir, true);
    }
    const entries: Array<string> = await this.context!.resourceManager.getRawFileList(rawDir);
    for (const name of entries) {
      const rawPath: string = `${rawDir}/${name}`;
      if (await this.isRawDir(rawPath)) {
        await this.extractDir(rawPath, onFile);
      } else {
        const content: Uint8Array = await this.context!.resourceManager.getRawFileContent(rawPath);
        const out: string = `${this.context!.filesDir}/${rawPath}`;
        const file = fs.openSync(out, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
        try {
          fs.writeSync(file.fd, content.buffer);
        } finally {
          fs.closeSync(file);
        }
        onFile();
      }
    }
  }

  private async isRawDir(rawPath: string): Promise<boolean> {
    try {
      const list: Array<string> = await this.context!.resourceManager.getRawFileList(rawPath);
      return list.length > 0;
    } catch (e) {
      return false;
    }
  }

  private readSync(filePath: string): ArrayBuffer | null {
    try {
      if (!fs.accessSync(filePath)) {
        return null;
      }
      const stat: fs.Stat = fs.statSync(filePath);
      const buf: ArrayBuffer = new ArrayBuffer(stat.size);
      const file = fs.openSync(filePath, fs.OpenMode.READ_ONLY);
      try {
        fs.readSync(file.fd, buf);
      } finally {
        fs.closeSync(file);
      }
      return buf;
    } catch (e) {
      return null;
    }
  }

  private mimeOf(path: string): string {
    if (path.endsWith('.html')) {
      return 'text/html';
    }
    if (path.endsWith('.js') || path.endsWith('.mjs')) {
      return 'text/javascript';
    }
    if (path.endsWith('.css')) {
      return 'text/css';
    }
    if (path.endsWith('.json') || path.endsWith('.txt')) {
      return 'application/json';
    }
    if (path.endsWith('.woff2')) {
      return 'font/woff2';
    }
    if (path.endsWith('.woff')) {
      return 'font/woff';
    }
    if (path.endsWith('.ttf')) {
      return 'font/ttf';
    }
    if (path.endsWith('.otf')) {
      return 'font/otf';
    }
    if (path.endsWith('.png')) {
      return 'image/png';
    }
    if (path.endsWith('.jpg') || path.endsWith('.jpeg')) {
      return 'image/jpeg';
    }
    if (path.endsWith('.svg')) {
      return 'image/svg+xml';
    }
    if (path.endsWith('.webp')) {
      return 'image/webp';
    }
    if (path.endsWith('.gif')) {
      return 'image/gif';
    }
    if (path.endsWith('.ico')) {
      return 'image/x-icon';
    }
    if (path.endsWith('.wasm')) {
      return 'application/wasm';
    }
    // book formats (readest.ohos.internal)
    if (path.endsWith('.epub')) {
      return 'application/epub+zip';
    }
    if (path.endsWith('.mobi') || path.endsWith('.azw3')) {
      return 'application/x-mobipocket-ebook';
    }
    if (path.endsWith('.pdf')) {
      return 'application/pdf';
    }
    if (path.endsWith('.cbz')) {
      return 'application/vnd.comicbook+zip';
    }
    if (path.endsWith('.fb2')) {
      return 'application/x-fictionbook+xml';
    }
    return 'application/octet-stream';
  }
}
