import './style.css';
import { createClient, type SupabaseClient } from '@supabase/supabase-js';

type RoleTab = 'worker' | 'business';
type StatusFilter = 'all' | 'pendingVerification' | 'verified' | 'rejected' | 'suspended';

interface ProfileRow {
  id: string;
  email: string | null;
  role: string | null;
  account_status: string | null;
  account_review_note: string | null;
  onboarding_done: boolean | null;
  created_at: string;
  updated_at: string;
  identity_snapshot: unknown;
}

interface KycRow {
  id: string;
  user_id: string;
  flow: string;
  document_type: string;
  storage_path: string;
  original_filename: string | null;
  content_type: string | null;
  created_at: string;
  review_status: string | null;
  reviewed_at: string | null;
  review_note: string | null;
}

const app = document.querySelector<HTMLDivElement>('#app');
if (!app) throw new Error('#app missing');

/** Project root only (e.g. `https://xxx.supabase.co`). Strips `/rest/v1` if copied from the SQL/REST section. */
function normalizeSupabaseProjectUrl(raw: string): string {
  let u = raw.trim().replace(/\/+$/, '');
  u = u.replace(/\/rest\/v1\/?$/i, '');
  return u.replace(/\/+$/, '');
}

const url = normalizeSupabaseProjectUrl(import.meta.env.VITE_SUPABASE_URL ?? '');
const anonKey = import.meta.env.VITE_SUPABASE_ANON_KEY?.trim() ?? '';

/** Example `.env` values are truthy but not real hosts — avoids ERR_NAME_NOT_RESOLVED / “Failed to fetch”. */
function isPlaceholderSupabaseEnv(projectUrl: string, key: string): boolean {
  const u = projectUrl.toLowerCase();
  const k = key.toLowerCase();
  if (u.includes('your_project')) return true;
  if (k === 'your_anon_key') return true;
  return false;
}

const supabaseConfigured = Boolean(url && anonKey && !isPlaceholderSupabaseEnv(url, anonKey));

function supabaseConfigDebugHtml(): string {
  const safeUrl = url ? escapeHtml(url) : '<em>(empty)</em>';
  const keyPrefix = anonKey ? escapeHtml(`${anonKey.slice(0, 12)}…`) : '<em>(empty)</em>';
  const placeholder = isPlaceholderSupabaseEnv(url, anonKey) ? 'yes' : 'no';
  return `<div class="muted" style="margin-top:10px;font-size:0.85em;line-height:1.35">
    <div><strong>Detected</strong></div>
    <div>URL: <code>${safeUrl}</code></div>
    <div>Anon key: <code>${keyPrefix}</code></div>
    <div>Placeholder: <code>${placeholder}</code></div>
  </div>`;
}

let supabase: SupabaseClient | null = null;
if (supabaseConfigured) {
  supabase = createClient(url, anonKey);
}

let view: 'login' | 'app' = 'login';
let roleTab: RoleTab = 'worker';
let statusFilter: StatusFilter = 'pendingVerification';
let profiles: ProfileRow[] = [];
let selectedId: string | null = null;
let kycDocs: KycRow[] = [];
let loadingList = false;
let loadingDetail = false;
/** Account-level RPC + refresh in progress (toolbar strip). */
let savingAccount = false;
/** Signed URL fetch before KYC viewer opens. */
let previewLoading = false;
let rejectModalUser: string | null = null;

function spinnerHtml(size: 'md' | 'sm'): string {
  const cls = size === 'md' ? 'spinner' : 'spinner spinner-sm';
  return `<div class="${cls}" role="progressbar" aria-busy="true" aria-label="Loading"></div>`;
}

/** Login password visibility toggle (initially “show” / eye). */
const passwordToggleEyeSvg = `<svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M2 12s3-7 10-7 10 7 10 7-3 7-10 7-10-7-10-7Z"/><circle cx="12" cy="12" r="3"/></svg>`;
const passwordToggleEyeOffSvg = `<svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M9.88 9.88a3 3 0 1 0 4.24 4.24"/><path d="M10.73 5.08A10.43 10.43 0 0 1 12 5c7 0 10 7 10 7a13.16 13.16 0 0 1-1.67 2.68"/><path d="M6.61 6.61A13.526 13.526 0 0 0 2 12s3 7 10 7a9.74 9.74 0 0 0 5.39-1.61"/><line x1="2" x2="22" y1="2" y2="22"/></svg>`;

function wirePasswordToggle(): void {
  const pwdInput = document.getElementById('password') as HTMLInputElement | null;
  const pwdToggle = document.getElementById('password-toggle');
  if (!pwdInput || !pwdToggle) return;
  const sync = (): void => {
    const hidden = pwdInput.type === 'password';
    pwdToggle.innerHTML = hidden ? passwordToggleEyeSvg : passwordToggleEyeOffSvg;
    pwdToggle.setAttribute('aria-label', hidden ? 'Show password' : 'Hide password');
    pwdToggle.setAttribute('title', hidden ? 'Show password' : 'Hide password');
    pwdToggle.setAttribute('aria-pressed', hidden ? 'false' : 'true');
  };
  pwdToggle.addEventListener('click', () => {
    pwdInput.type = pwdInput.type === 'password' ? 'text' : 'password';
    sync();
  });
  sync();
}

function loadingBlock(message: string, size: 'md' | 'sm' = 'md'): string {
  return `
    <div class="loading-block">
      ${spinnerHtml(size)}
      <span class="loading-block-text">${escapeHtml(message)}</span>
    </div>`;
}

function globalBusyLabel(): string {
  if (previewLoading) return 'Opening document…';
  if (savingAccount) return 'Saving account…';
  if (loadingList) return 'Loading accounts…';
  if (loadingDetail) return 'Loading documents…';
  return '';
}

function isPanelBusy(): boolean {
  return loadingList || loadingDetail || savingAccount || previewLoading;
}

function kycDocReviewBadgeClass(status: string | null | undefined): string {
  switch (status) {
    case 'approved':
      return 'badge-verified';
    case 'rejected':
      return 'badge-rejected';
    default:
      return 'badge-pending';
  }
}

function badgeClass(status: string | null): string {
  switch (status) {
    case 'verified':
      return 'badge-verified';
    case 'rejected':
      return 'badge-rejected';
    case 'suspended':
      return 'badge-suspended';
    case 'pendingVerification':
      return 'badge-pending';
    default:
      return 'badge-suspended';
  }
}

function formatDate(iso: string | null | undefined): string {
  if (!iso) return '—';
  try {
    return new Date(iso).toLocaleString();
  } catch {
    return iso;
  }
}

function strVal(v: unknown): string | null {
  if (v == null) return null;
  const s = String(v).trim();
  return s.length > 0 ? s : null;
}

/** Trade / partnership / corporate name from `profiles.identity_snapshot` (business onboarding). */
function businessDisplayName(snapshot: unknown): string | null {
  if (snapshot == null || typeof snapshot !== 'object') return null;
  const top = snapshot as Record<string, unknown>;
  let data: Record<string, unknown>;
  if (top.flow === 'business' && top.data != null && typeof top.data === 'object') {
    data = top.data as Record<string, unknown>;
  } else {
    data = top;
  }
  const kind = strVal(data.business_kind);
  const details = data.details;
  if (details == null || typeof details !== 'object') return null;
  const d = details as Record<string, unknown>;
  switch (kind) {
    case 'soleProprietorship': {
      const sp = d.sole_proprietorship;
      if (sp != null && typeof sp === 'object') {
        return strVal((sp as Record<string, unknown>).trade_name);
      }
      return null;
    }
    case 'partnership': {
      const pr = d.partnership;
      if (pr != null && typeof pr === 'object') {
        return strVal((pr as Record<string, unknown>).partnership_name);
      }
      return null;
    }
    case 'corporation': {
      const c = d.corporation;
      if (c != null && typeof c === 'object') {
        return strVal((c as Record<string, unknown>).corporate_name);
      }
      return null;
    }
    default:
      return null;
  }
}

/** Worker full name from `identity_snapshot` (wrapped or legacy shape). */
function workerDisplayName(snapshot: unknown): string | null {
  if (snapshot == null || typeof snapshot !== 'object') return null;
  const top = snapshot as Record<string, unknown>;
  let personal: unknown;
  if (top.flow === 'worker' && top.data != null && typeof top.data === 'object') {
    personal = (top.data as Record<string, unknown>).personal;
  } else {
    personal = top.personal;
  }
  if (personal != null && typeof personal === 'object') {
    return strVal((personal as Record<string, unknown>).full_name);
  }
  return null;
}

function profileTableDisplayName(p: ProfileRow, tab: RoleTab): string | null {
  return tab === 'business' ? businessDisplayName(p.identity_snapshot) : workerDisplayName(p.identity_snapshot);
}

async function ensureStaff(): Promise<boolean> {
  if (!supabase) return false;
  const { data: u } = await supabase.auth.getUser();
  const uid = u.user?.id;
  if (!uid) return false;
  const { data, error } = await supabase
    .from('profiles')
    .select('role')
    .eq('id', uid)
    .maybeSingle();
  if (error) {
    console.error(error);
    return false;
  }
  return data?.role === 'admin';
}

async function loadProfiles(): Promise<void> {
  if (!supabase) return;
  loadingList = true;
  if (view === 'app') renderApp();
  let q = supabase
    .from('profiles')
    .select(
      'id,email,role,account_status,account_review_note,onboarding_done,created_at,updated_at,identity_snapshot',
    )
    .eq('role', roleTab)
    .order('updated_at', { ascending: false });
  if (statusFilter !== 'all') {
    q = q.eq('account_status', statusFilter);
  }
  const { data, error } = await q;
  loadingList = false;
  if (error) {
    console.error(error);
    profiles = [];
  } else {
    profiles = (data ?? []) as ProfileRow[];
  }
  if (selectedId && !profiles.some((p) => p.id === selectedId)) {
    selectedId = profiles[0]?.id ?? null;
  }
  if (!selectedId && profiles.length) selectedId = profiles[0].id;
  await loadKycForSelection();
  if (view === 'app') renderApp();
}

async function loadKycForSelection(): Promise<void> {
  if (!supabase || !selectedId) {
    kycDocs = [];
    if (view === 'app') renderApp();
    return;
  }
  loadingDetail = true;
  if (view === 'app') renderApp();
  const { data, error } = await supabase
    .from('kyc_documents')
    .select('*')
    .eq('user_id', selectedId)
    .order('created_at', { ascending: true });
  loadingDetail = false;
  if (error) {
    console.error(error);
    kycDocs = [];
  } else {
    kycDocs = (data ?? []) as KycRow[];
  }
  if (view === 'app') renderApp();
}

async function getKycSignedUrl(path: string): Promise<string | null> {
  if (!supabase) return null;
  const { data, error } = await supabase.storage.from('kyc-documents').createSignedUrl(path, 3600);
  if (error || !data?.signedUrl) {
    alert(error?.message ?? 'Could not create download link');
    return null;
  }
  return data.signedUrl;
}

function isPdfContentType(ct: string | null | undefined): boolean {
  return (ct ?? '').toLowerCase().includes('pdf');
}

/** Full-screen inspect modal: zoom (wheel / +/-), pan (drag), PDF in iframe. */
function openKycInspectModal(signedUrl: string, title: string, contentType: string | null): void {
  const existing = document.getElementById('kyc-inspect-root');
  existing?.remove();

  const root = document.createElement('div');
  root.id = 'kyc-inspect-root';
  root.className = 'kyc-inspect-backdrop';
  const safeTitle = escapeHtml(title);
  const isPdf = isPdfContentType(contentType);

  root.innerHTML = `
    <div class="kyc-inspect-shell">
      <header class="kyc-inspect-bar">
        <span class="kyc-inspect-title">${safeTitle}</span>
        <div class="kyc-inspect-tools">
          ${
            isPdf
              ? ''
              : `
          <button type="button" class="btn btn-ghost btn-sm" id="kyc-zoom-out" title="Zoom out">−</button>
          <span class="kyc-zoom-label" id="kyc-zoom-pct">100%</span>
          <button type="button" class="btn btn-ghost btn-sm" id="kyc-zoom-in" title="Zoom in">+</button>
          <button type="button" class="btn btn-ghost btn-sm" id="kyc-zoom-reset" title="Reset pan & zoom">Reset</button>
          <button type="button" class="btn btn-ghost btn-sm" id="kyc-zoom-fit" title="Fit to view">Fit</button>
          `
          }
          <a class="btn btn-ghost btn-sm" href="${escapeAttr(signedUrl)}" target="_blank" rel="noopener noreferrer">New tab</a>
          <button type="button" class="btn btn-ghost btn-sm" id="kyc-inspect-close" title="Close (Esc)">Close</button>
        </div>
      </header>
      <div class="kyc-inspect-viewport ${isPdf ? 'kyc-inspect-viewport--pdf' : ''}" id="kyc-viewport">
        <div class="kyc-inspect-loading" id="kyc-media-loading" aria-live="polite">
          <div class="spinner"></div>
          <span class="kyc-inspect-loading-text">${isPdf ? 'Loading PDF…' : 'Loading image…'}</span>
        </div>
        ${
          isPdf
            ? `<iframe class="kyc-inspect-pdf" id="kyc-pdf-frame" src="${escapeAttr(signedUrl)}" title="${safeTitle}"></iframe>`
            : `<div class="kyc-inspect-frame" id="kyc-frame">
                 <img src="${escapeAttr(signedUrl)}" alt="${safeTitle}" id="kyc-img" draggable="false" />
               </div>`
        }
      </div>
      ${
        isPdf
          ? '<p class="kyc-inspect-hint">PDF preview — use browser controls inside the frame, or open in a new tab.</p>'
          : '<p class="kyc-inspect-hint">Scroll wheel to zoom · drag to pan · double-click to reset</p>'
      }
    </div>
  `;

  document.body.appendChild(root);

  let detachWindowDrag: (() => void) | null = null;

  const onKey = (e: KeyboardEvent): void => {
    if (e.key === 'Escape') close();
  };

  const close = (): void => {
    detachWindowDrag?.();
    detachWindowDrag = null;
    root.remove();
    document.removeEventListener('keydown', onKey);
  };

  document.addEventListener('keydown', onKey);

  root.addEventListener('click', (e) => {
    if (e.target === root) close();
  });

  document.getElementById('kyc-inspect-close')?.addEventListener('click', close);

  const mediaLoading = document.getElementById('kyc-media-loading');
  const hideMediaLoading = (): void => {
    mediaLoading?.classList.add('kyc-inspect-loading--done');
    window.setTimeout(() => mediaLoading?.remove(), 220);
  };
  const showMediaError = (msg: string): void => {
    if (!mediaLoading) return;
    mediaLoading.innerHTML = `<p class="kyc-inspect-loading-error">${escapeHtml(msg)}</p>`;
  };

  if (isPdf) {
    const pdfFrame = document.getElementById('kyc-pdf-frame') as HTMLIFrameElement | null;
    const slowPdfHint = window.setTimeout(() => {
      const hint = mediaLoading?.querySelector('.kyc-inspect-loading-text');
      if (hint && !mediaLoading?.classList.contains('kyc-inspect-loading--done')) {
        hint.textContent = 'Still loading… large PDFs can take a while. You can use New tab.';
      }
    }, 10000);
    const hidePdfLoading = (): void => {
      window.clearTimeout(slowPdfHint);
      hideMediaLoading();
    };
    if (pdfFrame) {
      pdfFrame.addEventListener('load', hidePdfLoading);
      pdfFrame.addEventListener('error', () => {
        window.clearTimeout(slowPdfHint);
        showMediaError('Could not load PDF. Use “New tab” to open it.');
      });
    }
    return;
  }

  const viewport = document.getElementById('kyc-viewport') as HTMLDivElement | null;
  const frame = document.getElementById('kyc-frame') as HTMLDivElement | null;
  const img = document.getElementById('kyc-img') as HTMLImageElement | null;
  const zoomPctEl = document.getElementById('kyc-zoom-pct');
  if (!viewport || !frame || !img || !zoomPctEl) return;

  let scale = 1;
  let tx = 0;
  let ty = 0;
  let dragging = false;
  let ptrId: number | null = null;
  let lastX = 0;
  let lastY = 0;

  const clampScale = (s: number): number => Math.min(8, Math.max(0.15, s));

  const apply = (): void => {
    frame.style.transform = `translate(${tx}px, ${ty}px) scale(${scale})`;
    zoomPctEl.textContent = `${Math.round(scale * 100)}%`;
  };

  const fitToView = (): void => {
    const nw = img.naturalWidth;
    const nh = img.naturalHeight;
    if (!nw || !nh) return;
    const rect = viewport.getBoundingClientRect();
    const pad = 32;
    const sx = (rect.width - pad) / nw;
    const sy = (rect.height - pad) / nh;
    scale = clampScale(Math.min(sx, sy, 1));
    tx = 0;
    ty = 0;
    apply();
  };

  document.getElementById('kyc-zoom-in')?.addEventListener('click', () => {
    scale = clampScale(scale * 1.2);
    apply();
  });
  document.getElementById('kyc-zoom-out')?.addEventListener('click', () => {
    scale = clampScale(scale / 1.2);
    apply();
  });
  document.getElementById('kyc-zoom-reset')?.addEventListener('click', () => {
    scale = 1;
    tx = 0;
    ty = 0;
    apply();
  });
  document.getElementById('kyc-zoom-fit')?.addEventListener('click', () => fitToView());

  viewport.addEventListener(
    'wheel',
    (e) => {
      e.preventDefault();
      const delta = e.deltaY > 0 ? -0.12 : 0.12;
      const next = clampScale(scale + delta * scale);
      scale = next;
      apply();
    },
    { passive: false },
  );

  img.addEventListener('dblclick', () => {
    scale = 1;
    tx = 0;
    ty = 0;
    apply();
  });

  const onDown = (clientX: number, clientY: number): void => {
    dragging = true;
    lastX = clientX;
    lastY = clientY;
    viewport.classList.add('grabbing');
  };
  const onMove = (clientX: number, clientY: number): void => {
    if (!dragging) return;
    tx += clientX - lastX;
    ty += clientY - lastY;
    lastX = clientX;
    lastY = clientY;
    apply();
  };
  const onUp = (): void => {
    dragging = false;
    ptrId = null;
    viewport.classList.remove('grabbing');
  };

  viewport.addEventListener('mousedown', (e) => {
    if (e.button !== 0) return;
    onDown(e.clientX, e.clientY);
  });
  const onWinMove = (e: MouseEvent): void => onMove(e.clientX, e.clientY);
  const onWinUp = (): void => onUp();
  window.addEventListener('mousemove', onWinMove);
  window.addEventListener('mouseup', onWinUp);
  detachWindowDrag = (): void => {
    window.removeEventListener('mousemove', onWinMove);
    window.removeEventListener('mouseup', onWinUp);
  };

  viewport.addEventListener(
    'touchstart',
    (e) => {
      if (e.touches.length !== 1) return;
      const t = e.touches[0];
      ptrId = t.identifier;
      onDown(t.clientX, t.clientY);
    },
    { passive: true },
  );
  viewport.addEventListener(
    'touchmove',
    (e) => {
      if (ptrId == null) return;
      const t = [...e.touches].find((x) => x.identifier === ptrId);
      if (!t) return;
      e.preventDefault();
      onMove(t.clientX, t.clientY);
    },
    { passive: false },
  );
  viewport.addEventListener('touchend', () => onUp());
  viewport.addEventListener('touchcancel', () => onUp());

  const slowImgHint = window.setTimeout(() => {
    const hint = mediaLoading?.querySelector('.kyc-inspect-loading-text');
    if (hint && !mediaLoading?.classList.contains('kyc-inspect-loading--done')) {
      hint.textContent = 'Still loading… large images can take a while. You can use New tab.';
    }
  }, 10000);

  img.addEventListener('load', () => {
    window.clearTimeout(slowImgHint);
    hideMediaLoading();
    fitToView();
  });
  img.addEventListener('error', () => {
    window.clearTimeout(slowImgHint);
    showMediaError('Could not load image. Use “New tab” or check the file.');
  });

  if (img.complete && img.naturalWidth > 0) {
    window.clearTimeout(slowImgHint);
    hideMediaLoading();
    fitToView();
  }
  apply();
}

async function openKycDocument(path: string, label: string, contentType: string | null): Promise<void> {
  previewLoading = true;
  if (view === 'app') renderApp();
  try {
    const signedUrl = await getKycSignedUrl(path);
    if (!signedUrl) return;
    openKycInspectModal(signedUrl, label, contentType);
  } finally {
    previewLoading = false;
    if (view === 'app') renderApp();
  }
}

async function setReview(userId: string, status: string, note: string | null): Promise<void> {
  if (!supabase) return;
  savingAccount = true;
  if (view === 'app') renderApp();
  try {
    const { error } = await supabase.rpc('admin_set_account_review', {
      p_user_id: userId,
      p_status: status,
      p_note: note,
    });
    if (error) {
      alert(error.message);
      return;
    }
    await loadProfiles();
  } finally {
    savingAccount = false;
    if (view === 'app') renderApp();
  }
}

async function setKycDocumentReview(
  documentId: string,
  status: 'pending' | 'approved' | 'rejected',
  note: string | null,
): Promise<void> {
  if (!supabase) return;
  const { error } = await supabase.rpc('admin_set_kyc_document_review', {
    p_kyc_document_id: documentId,
    p_note: note,
    p_status: status,
  });
  if (error) {
    alert(error.message);
    return;
  }
  await loadKycForSelection();
}

function renderLogin(): void {
  if (!app) return;
  app.innerHTML = `
    <div class="login-page">
      <div class="login-card">
        <div class="login-brand">
          <span class="login-brand-mark" aria-hidden="true">N</span>
          <div class="login-brand-text">
            <h1>Nexora</h1>
            <span class="login-brand-badge">Staff console</span>
          </div>
        </div>
        <p class="sub">Sign in with your admin account. Use a dedicated staff email — not a worker or business app login.</p>
        ${
          !supabaseConfigured
            ? `<div class="error">Set real values for <code>VITE_SUPABASE_URL</code> and <code>VITE_SUPABASE_ANON_KEY</code> in <code>admin-web/.env</code> (Supabase Dashboard → Settings → API — same as the Flutter app’s <code>assets/supabase.env</code>). Use the project root URL like <code>https://xxx.supabase.co</code> (not <code>/rest/v1</code>). Then restart <code>npm run dev</code>.${supabaseConfigDebugHtml()}</div>`
            : `
        <form id="login-form">
          <div class="field">
            <label for="email">Email</label>
            <input id="email" name="email" type="email" autocomplete="username" required />
          </div>
          <div class="field">
            <label for="password">Password</label>
            <div class="password-field-wrap">
              <input id="password" name="password" type="password" autocomplete="current-password" required />
              <button type="button" class="password-toggle" id="password-toggle">${passwordToggleEyeSvg}</button>
            </div>
          </div>
          <button type="submit" class="btn btn-primary" id="login-btn">
            <span class="login-btn-inner">
              <span class="login-btn-label">Sign in</span>
              ${spinnerHtml('sm')}
            </span>
          </button>
          <div id="login-err" class="error" style="display:none"></div>
        </form>`
        }
      </div>
      <p class="login-foot">Accounts are managed in Supabase. There is no sign-up on this page.</p>
    </div>
  `;

  wirePasswordToggle();

  const form = document.getElementById('login-form');
  const errEl = document.getElementById('login-err');
  form?.addEventListener('submit', async (e) => {
    e.preventDefault();
    if (!supabase || !errEl) return;
    const btn = document.getElementById('login-btn') as HTMLButtonElement;
    const email = (document.getElementById('email') as HTMLInputElement).value.trim();
    const password = (document.getElementById('password') as HTMLInputElement).value;
    errEl.style.display = 'none';
    btn.disabled = true;
    btn.classList.add('is-loading');
    try {
      const { error } = await supabase.auth.signInWithPassword({ email, password });
      if (error) {
        errEl.textContent = error.message;
        errEl.style.display = 'block';
        return;
      }
      const ok = await ensureStaff();
      if (!ok) {
        await supabase.auth.signOut();
        errEl.textContent =
          'This account is not marked as admin. In SQL run: update public.profiles set role = \'admin\' where email = \'your@email\';';
        errEl.style.display = 'block';
        return;
      }
      view = 'app';
      await loadProfiles();
    } finally {
      btn.classList.remove('is-loading');
      btn.disabled = false;
    }
  });
}

function renderRejectModal(): string {
  if (!rejectModalUser) return '';
  return `
    <div class="modal-backdrop" id="reject-backdrop">
      <div class="modal modal-sheet">
        <h4>Reject verification</h4>
        <p class="muted" style="margin:0 0 10px">Optional note (stored on the profile for your team; users may see this later).</p>
        <textarea id="reject-note" placeholder="Reason for rejection…"></textarea>
        <div class="modal-actions">
          <button type="button" class="btn btn-ghost" id="reject-cancel">Cancel</button>
          <button type="button" class="btn btn-danger" id="reject-confirm">Reject account</button>
        </div>
      </div>
    </div>
  `;
}

function renderApp(): void {
  if (!app) return;
  const selected = profiles.find((p) => p.id === selectedId) ?? null;
  const busyLabel = globalBusyLabel();
  const panelLocked = loadingList || loadingDetail || savingAccount || previewLoading;

  app.innerHTML = `
    <div class="layout">
      <aside class="sidebar">
        <div class="sidebar-brand">
          <span class="sidebar-brand-mark" aria-hidden="true">N</span>
          <div>
            <div class="sidebar-brand-title">Nexora</div>
            <div class="sidebar-brand-sub">Verification</div>
          </div>
        </div>
        <p class="sidebar-label">Queues</p>
        <button type="button" class="nav-btn ${roleTab === 'worker' ? 'active' : ''}" data-tab="worker" ${loadingList ? 'disabled' : ''}>
          <span class="nav-btn-icon" aria-hidden="true">◆</span>
          Workers
        </button>
        <button type="button" class="nav-btn ${roleTab === 'business' ? 'active' : ''}" data-tab="business" ${loadingList ? 'disabled' : ''}>
          <span class="nav-btn-icon" aria-hidden="true">◇</span>
          Businesses
        </button>
        <div class="sidebar-footer">
          <button type="button" class="btn btn-sidebar-logout btn-sm" id="logout-btn">Sign out</button>
        </div>
      </aside>
      <main class="main">
        <div class="main-inner">
        ${
          busyLabel
            ? `<div class="busy-strip" aria-live="polite"><div class="busy-strip-bar"></div><span class="busy-strip-text">${escapeHtml(busyLabel)}</span></div>`
            : ''
        }
        <header class="page-header">
          <div class="page-header-titles">
            <h2 class="page-title">${roleTab === 'worker' ? 'Workers' : 'Businesses'}</h2>
            <p class="page-subtitle">Review submissions and KYC documents</p>
          </div>
          <div class="chips" role="group" aria-label="Filter by status">
            ${(
              [
                ['pendingVerification', 'Pending'],
                ['all', 'All'],
                ['verified', 'Verified'],
                ['rejected', 'Rejected'],
                ['suspended', 'Suspended'],
              ] as const
            )
              .map(
                ([v, label]) =>
                  `<button type="button" class="chip ${statusFilter === v ? 'on' : ''}" data-status="${v}" ${loadingList ? 'disabled' : ''}>${label}</button>`,
              )
              .join('')}
          </div>
        </header>
        <div class="workspace-grid">
          <div class="table-card">
            <div class="table-wrap">
              ${
                loadingList
                  ? loadingBlock('Loading accounts…', 'md')
                  : profiles.length === 0
                    ? '<div class="empty">No accounts in this view.</div>'
                    : `<table>
                <thead><tr>
                  <th>${roleTab === 'business' ? 'Business name' : 'Name'}</th>
                  <th>Email</th>
                  <th>Status</th>
                  <th>Onboarding</th>
                  <th>Updated</th>
                </tr></thead>
                <tbody>
                  ${profiles
                    .map(
                      (p) => `
                    <tr class="row-clickable ${p.id === selectedId ? 'selected' : ''}" data-id="${p.id}">
                      <td><strong>${escapeHtml(profileTableDisplayName(p, roleTab) ?? '—')}</strong></td>
                      <td>${p.email ?? '—'}</td>
                      <td><span class="badge ${badgeClass(p.account_status)}">${p.account_status ?? '—'}</span></td>
                      <td>${p.onboarding_done ? 'Done' : '—'}</td>
                      <td>${formatDate(p.updated_at)}</td>
                    </tr>`,
                    )
                    .join('')}
                </tbody>
              </table>`
              }
            </div>
          </div>
          <aside class="panel review-panel">
            <div class="panel-header">
              <h3>Review</h3>
              <span class="panel-header-hint">Selected account</span>
            </div>
            ${
              !selected
                ? '<p class="panel-empty muted">Select a row in the table to open documents and the identity snapshot.</p>'
                : `
              <div class="panel-profile">
                <p class="panel-profile-name">${escapeHtml(profileTableDisplayName(selected, roleTab) ?? '—')}</p>
                <p class="panel-profile-email">${escapeHtml(selected.email ?? selected.id)}</p>
                <p class="panel-profile-id"><span class="muted">User ID</span> <code>${selected.id}</code></p>
              </div>
              ${
                selected.account_review_note
                  ? `<div class="panel-note"><span class="muted">Last note</span> ${escapeHtml(selected.account_review_note)}</div>`
                  : ''
              }
              <div class="panel-section">
              <h4 class="panel-section-title">KYC documents</h4>
              <p class="panel-section-hint muted">Upload order · per-file review · account buttons below set overall status</p>
              ${
                loadingDetail
                  ? loadingBlock('Loading documents…', 'sm')
                  : kycDocs.length === 0
                    ? '<p class="muted">No uploads indexed yet.</p>'
                    : `<ul class="doc-list">${kycDocs
                        .map((d, i) => {
                          const st = d.review_status ?? 'pending';
                          const note =
                            d.review_note != null && d.review_note !== ''
                              ? `<span class="muted doc-note">${escapeHtml(d.review_note)}</span>`
                              : '';
                          const approveBtn =
                            st === 'approved'
                              ? `<button type="button" class="btn btn-cancel-approve btn-sm" data-kyc-pending="${escapeAttr(d.id)}" title="Mark this file as pending again" ${panelLocked ? 'disabled' : ''}>Cancel approve</button>`
                              : `<button type="button" class="btn btn-success btn-sm" data-kyc-approve="${escapeAttr(d.id)}" ${panelLocked ? 'disabled' : ''}>Approve</button>`;
                          const pendingBtn =
                            st === 'approved'
                              ? ''
                              : `<button type="button" class="btn btn-ghost btn-sm" data-kyc-pending="${escapeAttr(d.id)}" ${panelLocked ? 'disabled' : ''}>Pending</button>`;
                          return `
                      <li class="doc-item">
                        <div class="doc-item-main">
                          <span class="doc-idx">${i + 1}.</span>
                          <div class="doc-item-text">
                            <div>
                              <strong>${escapeHtml(d.document_type)}</strong>
                              <span class="muted"> · ${escapeHtml(d.flow)}</span>
                              <span class="badge ${kycDocReviewBadgeClass(st)} doc-badge">${escapeHtml(st)}</span>
                            </div>
                            ${note}
                            <div class="muted doc-meta">${formatDate(d.reviewed_at ?? d.created_at)}</div>
                          </div>
                        </div>
                        <div class="doc-item-actions">
                          <button type="button" class="btn btn-ghost btn-sm" data-open="${escapeAttr(d.storage_path)}" data-doc-label="${escapeAttr(`${d.document_type} · ${d.flow}`)}" data-content-type="${escapeAttr(d.content_type ?? '')}" ${panelLocked ? 'disabled' : ''}>Open</button>
                          ${approveBtn}
                          <button type="button" class="btn btn-danger btn-sm" data-kyc-reject="${escapeAttr(d.id)}" ${panelLocked ? 'disabled' : ''}>Reject</button>
                          ${pendingBtn}
                        </div>
                      </li>`;
                        })
                        .join('')}</ul>`
              }
              </div>
              <div class="panel-section">
              <h4 class="panel-section-title">Identity snapshot</h4>
              <div class="json-preview">${escapeHtml(JSON.stringify(selected.identity_snapshot ?? {}, null, 2))}</div>
              </div>
              <div class="panel-actions actions"${panelLocked ? ' data-busy="1"' : ''}>
                <button type="button" class="btn btn-success btn-sm" data-action="verify" data-uid="${escapeAttr(selected.id)}" ${panelLocked ? 'disabled' : ''}>Approve (verified)</button>
                <button type="button" class="btn btn-danger btn-sm" data-action="reject" data-uid="${escapeAttr(selected.id)}" ${panelLocked ? 'disabled' : ''}>Reject</button>
                <button type="button" class="btn btn-ghost btn-sm" data-action="pending" data-uid="${escapeAttr(selected.id)}" ${panelLocked ? 'disabled' : ''}>Mark pending</button>
                <button type="button" class="btn btn-ghost btn-sm" data-action="suspend" data-uid="${escapeAttr(selected.id)}" ${panelLocked ? 'disabled' : ''}>Suspend</button>
              </div>
            `
            }
          </aside>
        </div>
        </div>
      </main>
    </div>
    ${renderRejectModal()}
  `;

  document.querySelectorAll('[data-tab]').forEach((el) => {
    el.addEventListener('click', () => {
      if (loadingList) return;
      const t = el.getAttribute('data-tab') as RoleTab;
      if (t === roleTab) return;
      roleTab = t;
      selectedId = null;
      void loadProfiles();
    });
  });

  document.querySelectorAll('[data-status]').forEach((el) => {
    el.addEventListener('click', () => {
      if (loadingList) return;
      const s = el.getAttribute('data-status') as StatusFilter;
      if (s === statusFilter) return;
      statusFilter = s;
      selectedId = null;
      void loadProfiles();
    });
  });

  document.getElementById('logout-btn')?.addEventListener('click', async () => {
    await supabase?.auth.signOut();
    selectedId = null;
    profiles = [];
    view = 'login';
    renderLogin();
  });

  document.querySelectorAll('tr[data-id]').forEach((el) => {
    el.addEventListener('click', () => {
      if (loadingList) return;
      const id = el.getAttribute('data-id');
      if (!id || id === selectedId) return;
      selectedId = id;
      void loadKycForSelection();
    });
  });

  document.querySelectorAll('[data-open]').forEach((el) => {
    el.addEventListener('click', (e) => {
      e.stopPropagation();
      const path = el.getAttribute('data-open');
      const label = el.getAttribute('data-doc-label') ?? 'Document';
      const ct = el.getAttribute('data-content-type');
      if (path) void openKycDocument(path, label, ct || null);
    });
  });

  document.querySelectorAll('[data-kyc-approve]').forEach((el) => {
    el.addEventListener('click', (e) => {
      e.stopPropagation();
      const id = el.getAttribute('data-kyc-approve');
      if (id) void setKycDocumentReview(id, 'approved', null);
    });
  });
  document.querySelectorAll('[data-kyc-reject]').forEach((el) => {
    el.addEventListener('click', (e) => {
      e.stopPropagation();
      const id = el.getAttribute('data-kyc-reject');
      if (!id) return;
      const note = window.prompt('Optional note for this document (shown in admin):')?.trim() || null;
      void setKycDocumentReview(id, 'rejected', note);
    });
  });
  document.querySelectorAll('[data-kyc-pending]').forEach((el) => {
    el.addEventListener('click', (e) => {
      e.stopPropagation();
      const id = el.getAttribute('data-kyc-pending');
      if (id) void setKycDocumentReview(id, 'pending', null);
    });
  });

  document.querySelectorAll('[data-action]').forEach((el) => {
    el.addEventListener('click', () => {
      if (isPanelBusy()) return;
      const action = el.getAttribute('data-action');
      const uid = el.getAttribute('data-uid');
      if (!uid) return;
      if (action === 'verify') void setReview(uid, 'verified', null);
      if (action === 'pending') void setReview(uid, 'pendingVerification', null);
      if (action === 'suspend') void setReview(uid, 'suspended', null);
      if (action === 'reject') {
        rejectModalUser = uid;
        queueMicrotask(() => renderApp());
      }
    });
  });

  bindRejectModal();
}

function bindRejectModal(): void {
  document.getElementById('reject-cancel')?.addEventListener('click', () => {
    rejectModalUser = null;
    renderApp();
  });
  document.getElementById('reject-backdrop')?.addEventListener('click', (e) => {
    if (e.target === e.currentTarget) {
      rejectModalUser = null;
      renderApp();
    }
  });
  document.getElementById('reject-confirm')?.addEventListener('click', async () => {
    if (!rejectModalUser) return;
    const note = (document.getElementById('reject-note') as HTMLTextAreaElement)?.value.trim() || null;
    const uid = rejectModalUser;
    rejectModalUser = null;
    renderApp();
    await setReview(uid, 'rejected', note);
  });
}

function escapeHtml(s: string): string {
  return s
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;');
}

function escapeAttr(s: string): string {
  return escapeHtml(s).replace(/'/g, '&#39;');
}

async function init(): Promise<void> {
  if (!supabase) {
    view = 'login';
    renderLogin();
    return;
  }
  const { data: { session } } = await supabase.auth.getSession();
  if (!session) {
    view = 'login';
    renderLogin();
    return;
  }
  const ok = await ensureStaff();
  if (!ok) {
    await supabase.auth.signOut();
    view = 'login';
    renderLogin();
    return;
  }
  view = 'app';
  await loadProfiles();
}

supabase?.auth.onAuthStateChange((_event, session) => {
  if (!session) {
    view = 'login';
    renderLogin();
  }
});

void init();
