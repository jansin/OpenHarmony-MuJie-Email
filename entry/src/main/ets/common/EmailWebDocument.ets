import { Email } from '../models/Email';
import { Utils } from './Utils';

/** 转义为 HTML 文本节点安全内容 */
export function escapeHtmlText(s: string): string {
  if (!s) {
    return '';
  }
  return s
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;');
}

/** 邮件 HTML 片段净化（纯 ArkTS 正则；不依赖 ohpm 上不可用的 htmlparser2 / sanitize-html 等 npm 模块）。 */
function sanitizeEmailHtmlRegex(html: string): string {
  let h: string = html.trim();
  h = h.replace(/<script[\s\S]*?<\/script>/gi, '');
  h = h.replace(/<noscript[\s\S]*?<\/noscript>/gi, '');
  h = h.replace(/<iframe[\s\S]*?<\/iframe>/gi, '');
  h = h.replace(/<object[\s\S]*?<\/object>/gi, '');
  h = h.replace(/<embed[^>]*>/gi, '');
  h = h.replace(/<applet[\s\S]*?<\/applet>/gi, '');
  h = h.replace(/<link[^>]*>/gi, '');
  h = h.replace(/<meta[^>]*http-equiv\s*=\s*['"]?refresh['"]?[^>]*>/gi, '');
  h = h.replace(/<base[^>]*>/gi, '');
  h = h.replace(/\son\w+\s*=\s*("[^"]*"|'[^']*'|[^\s>]+)/gi, ' ');
  h = h.replace(/\sformaction\s*=\s*("[^"]*"|'[^']*'|[^\s>]+)/gi, ' ');
  h = h.replace(/<form[^>]*>/gi, '<div class="mail-form">');
  h = h.replace(/<\/form>/gi, '</div>');
  h = h.replace(/href\s*=\s*("[^"]*"|'[^']*')/gi, (full: string, q: string) => {
    const v: string = q.toLowerCase();
    if (v.indexOf('javascript:') >= 0 || v.indexOf('vbscript:') >= 0 || v.indexOf('data:text/html') >= 0) {
      return 'href="#"';
    }
    return full;
  });
  h = h.replace(/href\s*=\s*([^\s>]+)/gi, (full: string, raw: string) => {
    const v: string = raw.toLowerCase();
    if (v.indexOf('javascript:') >= 0 || v.indexOf('vbscript:') >= 0 || v.indexOf('data:text/html') >= 0) {
      return 'href="#"';
    }
    return full;
  });
  h = h.replace(/src\s*=\s*("[^"]*"|'[^']*')/gi, (full: string, q: string) => {
    const v: string = q.toLowerCase();
    if (v.indexOf('javascript:') >= 0 || v.indexOf('vbscript:') >= 0 || v.indexOf('data:text/html') >= 0) {
      return 'src="#"';
    }
    return full;
  });
  h = h.replace(/src\s*=\s*([^\s>]+)/gi, (full: string, raw: string) => {
    const v: string = raw.toLowerCase();
    if (v.indexOf('javascript:') >= 0 || v.indexOf('vbscript:') >= 0 || v.indexOf('data:text/html') >= 0) {
      return 'src="#"';
    }
    return full;
  });
  h = h.replace(/url\s*\(\s*['"]?\s*javascript:/gi, 'url(#blocked');
  return h;
}

export function sanitizeEmailHtmlFragment(html: string): string {
  return sanitizeEmailHtmlRegex(html);
}

function decodeBasicHtmlEntities(s: string): string {
  return s
    .replace(/&lt;/g, '<')
    .replace(/&gt;/g, '>')
    .replace(/&quot;/g, '"')
    .replace(/&#39;/g, "'")
    .replace(/&apos;/g, "'")
    .replace(/&amp;/g, '&');
}

function looksLikeHtmlContent(s: string): boolean {
  const head = s.trim().substring(0, Math.min(4096, s.length));
  if (/<\/?(html|body|head|table|tbody|tr|td|div|p|br|span|img|a|style|meta)\b/i.test(head)) {
    return true;
  }
  return /&lt;\/?(html|body|head|table|tbody|tr|td|div|p|br|span|img|a|style|meta)\b/i.test(head);
}

function normalizePossiblyEscapedHtml(s: string): string {
  const t = s.trim();
  if (/&lt;\/?(html|body|head|table|tbody|tr|td|div|p|br|span|img|a|style|meta)\b/i.test(t)) {
    return decodeBasicHtmlEntities(t);
  }
  return t;
}

function isImageUrl(url: string): boolean {
  return /\.(png|jpe?g|gif|webp|bmp|svg)(\?[^"'<>]*)?$/i.test(url);
}

function plainTextToReadableHtml(text: string): string {
  const escaped = escapeHtmlText(text);
  const linked = escaped.replace(/https?:\/\/[^\s<>"']+/gi, (url: string) => {
    const clean = url.replace(/[),.;!?]+$/g, '');
    const suffix = url.substring(clean.length);
    if (isImageUrl(clean)) {
      return `<figure><img src="${clean}" alt=""/><figcaption><a href="${clean}">${clean}</a></figcaption></figure>${suffix}`;
    }
    return `<a href="${clean}">${clean}</a>${suffix}`;
  });
  return linked
    .replace(/\r\n/g, '\n')
    .replace(/\r/g, '\n')
    .split('\n')
    .map((line: string) => line.length > 0 ? line : '&nbsp;')
    .join('<br/>');
}

/**
 * CSP：只拦脚本与插件。不设 base-uri（与阅读器内合法 base 标签冲突时部分内核会白屏）。
 * 图片/样式由 Web 组件 imageAccess / onlineImageAccess 等宿主策略约束（mixedMode 视 SDK 而定）。
 */
export function getEmailViewerCspMeta(): string {
  return '<meta http-equiv="Content-Security-Policy" content="default-src * data: blob:; script-src \'none\'; object-src \'none\'; style-src \'unsafe-inline\' *; img-src * data: blob: http: https:; media-src *;"/>';
}

/**
 * 阅读器排版：标题/列表/表格/代码块、横向滚动、暗色对比。
 * @param compact 写邮件页引用区略紧凑
 */
export function getEmailReadabilityCss(isDark: boolean, compact: boolean, surfaceBg?: string): string {
  const bg = surfaceBg !== undefined && surfaceBg.length > 0 ? surfaceBg : (isDark ? '#161616' : '#ffffff');
  const fg = isDark ? '#e8eaed' : '#202124';
  const muted = isDark ? '#9aa0a6' : '#5f6368';
  const link = isDark ? '#8ab4f8' : '#1a73e8';
  const border = isDark ? '#3c4043' : '#dadce0';
  const codeBg = isDark ? '#2d2d2d' : '#f1f3f4';
  const basePx = compact ? 14 : 16;
  const lh = compact ? 1.5 : 1.55;
  const padY = compact ? '10px' : '14px';
  const padX = compact ? '12px' : '16px';

  return `
  html,body{margin:0;padding:0;background-color:${bg};color:${fg};color-scheme:${isDark ? 'dark' : 'light'};}
  body{padding:${padY} ${padX} 28px;font-size:${basePx}px;line-height:${lh};
    font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,'Helvetica Neue',Arial,'PingFang SC','Hiragino Sans GB','Microsoft YaHei',sans-serif;
    word-wrap:break-word;overflow-wrap:anywhere;-webkit-text-size-adjust:100%;}
  .mail-root{max-width:100%;background-color:transparent;}
  .mail-wrap{overflow-x:auto;-webkit-overflow-scrolling:touch;max-width:100%;background-color:transparent;}
  a{color:${link};text-decoration:none;word-break:break-all;}
  a:active{opacity:0.85;}
  img,video{max-width:100% !important;height:auto !important;border-radius:4px;}
  figure{margin:10px 0;}
  figcaption{font-size:12px;color:${muted};margin-top:4px;}
  h1,h2,h3,h4,h5,h6{margin:0.55em 0 0.3em;font-weight:600;line-height:1.28;color:${fg};}
  h1{font-size:1.35em;} h2{font-size:1.22em;} h3{font-size:1.12em;}
  h4,h5,h6{font-size:1.05em;}
  p{margin:0.55em 0;}
  ul,ol{padding-left:1.35em;margin:0.45em 0;}
  li{margin:0.2em 0;}
  blockquote{margin:10px 0;padding:10px 14px;border-left:3px solid ${link};
    background-color:${isDark ? '#252525' : '#f1f3f4'};color:${muted};font-size:${compact ? 13 : 14}px;}
  hr{border:none;border-top:1px solid ${border};margin:18px 0;}
  table{max-width:100%;border-collapse:collapse;font-size:${compact ? 13 : 14}px;}
  th,td{border:1px solid ${border};padding:6px 8px;text-align:start;vertical-align:top;word-break:break-word;}
  th{background-color:${isDark ? '#2a2a2a' : '#f8f9fa'};}
  pre:not(.plain){overflow-x:auto;background-color:${codeBg};padding:10px 12px;border-radius:8px;font-size:13px;line-height:1.45;margin:10px 0;}
  code,kbd,samp{font-family:ui-monospace,SFMono-Regular,Menlo,Consolas,monospace;}
  code:not(pre code){background-color:${codeBg};padding:2px 6px;border-radius:4px;font-size:0.92em;}
  pre.plain{white-space:pre-wrap;word-wrap:break-word;font:inherit;color:${fg};margin:0;}
  .plain-text{white-space:normal;}
  .mail-form{margin:4px 0;}
  `;
}

/** 去掉完整文档外壳，避免阅读器再包一层 html/body 导致结构错乱或白屏 */
export function normalizeEmailHtmlFragment(html: string): string {
  let t = html.trim();
  const low = t.toLowerCase();
  const openIdx = low.indexOf('<body');
  if (openIdx >= 0) {
    const fromOpen = t.substring(openIdx);
    const openTag = fromOpen.match(/^<body\b[^>]*>/i);
    if (openTag !== null && openTag[0] !== undefined) {
      const start = openIdx + openTag[0].length;
      const closeIdx = low.lastIndexOf('</body>');
      if (closeIdx > start) {
        return t.substring(start, closeIdx).trim();
      }
      return t.substring(start).trim();
    }
  }
  t = t.replace(/<head\b[^>]*>[\s\S]*?<\/head>/gi, '');
  t = t.replace(/<\/?html[^>]*>/gi, '');
  t = t.replace(/<\/?body\b[^>]*>/gi, '');
  return t.trim();
}

function stripNullChars(s: string): string {
  return s.replace(/\u0000/g, '');
}

/**
 * 包装为独立 HTML 文档，供 Web 组件 loadData 使用
 */
export function buildEmailWebDocument(html: string | undefined, plainText: string | undefined,
  isDark: boolean): string {
  const inner = buildEmailBodyHtmlFragment(html, plainText);

  return stripNullChars(`<!DOCTYPE html><html><head>
<meta charset="utf-8"/>
<meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=4,user-scalable=yes"/>
${getEmailViewerCspMeta()}
<base target="_blank"/>
<style>${getEmailReadabilityCss(isDark, false)}</style>
</head><body><div class="mail-root mail-wrap">${inner}</div></body></html>`);
}

export function buildEmailBodyHtmlFragment(html: string | undefined, plainText: string | undefined): string {
  const rawHtml = html !== undefined && html !== null ? html.trim() : '';
  const rawText = plainText !== undefined && plainText !== null ? plainText.trim() : '';
  let inner: string;
  if (rawHtml.length > 0) {
    inner = normalizeEmailHtmlFragment(sanitizeEmailHtmlFragment(normalizePossiblyEscapedHtml(rawHtml)));
  } else if (rawText.length > 0 && looksLikeHtmlContent(rawText)) {
    inner = normalizeEmailHtmlFragment(sanitizeEmailHtmlFragment(normalizePossiblyEscapedHtml(rawText)));
  } else {
    inner = `<div class="plain-text">${plainTextToReadableHtml(rawText)}</div>`;
  }
  return stripNullChars('<div style="width:90%;max-width:90%;margin-left:auto;margin-right:auto;">' + inner + '</div>');
}


