/**
 * 在本机用 Node 测 IMAP SSL 登录（与 App 内引号 LOGIN 行为一致）。
 * PowerShell:
 *   $env:IMAP_USER="你的邮箱"
 *   $env:IMAP_PASS="授权码"
 *   node scripts/imap_selftest.mjs
 * 可选: IMAP_HOST（默认 imap.qq.com）、IMAP_PORT（默认 993）
 */
import tls from 'node:tls';

function quote(s) {
  return '"' + s.replace(/\\/g, '\\\\').replace(/"/g, '\\"') + '"';
}

const host = process.env.IMAP_HOST || 'imap.qq.com';
const port = parseInt(process.env.IMAP_PORT || '993', 10);
const user = process.env.IMAP_USER || '';
const pass = process.env.IMAP_PASS || '';

if (!user || !pass) {
  console.error('请设置环境变量 IMAP_USER、IMAP_PASS');
  process.exit(1);
}

let buf = '';

function findTaggedStart(tag) {
  const p = tag + ' ';
  if (buf.startsWith(p)) return 0;
  const a = buf.indexOf('\r\n' + p);
  if (a >= 0) return a + 2;
  const b = buf.indexOf('\n' + p);
  if (b >= 0) return b + 1;
  return -1;
}

function tryExtractTaggedLine(tag) {
  const start = findTaggedStart(tag);
  if (start < 0) return null;
  const rest = buf.slice(start);
  let end = rest.indexOf('\r\n');
  let sep = 2;
  if (end < 0) {
    end = rest.indexOf('\n');
    sep = 1;
  }
  if (end < 0) return null;
  const line = rest.slice(0, end);
  buf = buf.slice(start + end + sep);
  return line;
}

const sock = tls.connect(
  { host, port, servername: host, rejectUnauthorized: true },
  () => console.log('[1] TLS 已连接', host + ':' + port)
);

sock.on('data', (c) => {
  buf += c.toString('utf8');
});

sock.on('error', (e) => {
  console.error('[ERR]', e.message);
  process.exit(2);
});

async function run() {
  await new Promise((r) => setTimeout(r, 1200));
  console.log('[2] 当前缓冲区(前800字):\n', buf.slice(0, 800));
  if (!/OK|PREAUTH/i.test(buf)) {
    console.error('[FAIL] 未见 IMAP 欢迎 OK');
    process.exit(3);
  }

  const tag = 't001';
  const line = `${tag} LOGIN ${quote(user)} ${quote(pass)}\r\n`;
  console.log('[3] 发送:', line.trim());
  sock.write(line);

  const deadline = Date.now() + 20000;
  let reply = null;
  while (Date.now() < deadline) {
    reply = tryExtractTaggedLine(tag);
    if (reply !== null) break;
    await new Promise((r) => setTimeout(r, 40));
  }

  if (reply === null) {
    console.error('[FAIL] 超时。剩余缓冲区前500字:', buf.slice(0, 500));
    process.exit(4);
  }

  console.log('[4] 带标签行:', reply);
  if (/^\s*t\d+\s+OK\b/i.test(reply)) {
    console.log('[OK] 登录成功');
    try {
      sock.write('t002 LOGOUT\r\n');
    } catch (_) {}
    process.exit(0);
  }

  console.error('[FAIL] 登录失败（请检查网页是否开启 IMAP、授权码是否有效）');
  process.exit(5);
}

run().catch((e) => {
  console.error(e);
  process.exit(9);
});
