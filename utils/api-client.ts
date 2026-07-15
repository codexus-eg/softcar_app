import { API_BASE_URL } from './constants';

export type MobileLoginSession = {
  token: string;
  user: {
    role: string;
  };
};

export function parseArrayPayload<T>(payload: unknown, key = 'data'): T[] {
  if (Array.isArray(payload)) return payload as T[];

  if (payload && typeof payload === 'object') {
    const record = payload as Record<string, unknown>;
    if (Array.isArray(record[key])) return record[key] as T[];
  }

  throw new Error('تعذر قراءة بيانات التطبيق. حدّث الصفحة ثم حاول مرة أخرى.');
}

export function parseMobileLoginSession(payload: unknown): MobileLoginSession {
  const record = payload && typeof payload === 'object' ? payload as Record<string, any> : {};
  const candidate =
    record.data && typeof record.data === 'object'
      ? record.data as Record<string, any>
      : record;

  if (
    typeof candidate.token !== 'string' ||
    !candidate.token.trim() ||
    !candidate.user ||
    typeof candidate.user !== 'object' ||
    typeof candidate.user.role !== 'string' ||
    !candidate.user.role.trim()
  ) {
    throw new Error('تعذر قراءة بيانات تسجيل الدخول. حدّث التطبيق ثم حاول مرة أخرى.');
  }

  return candidate as MobileLoginSession;
}

export async function apiRequest<T>(path: string, token: string, options: RequestInit = {}): Promise<T> {
  const response = await fetch(`${API_BASE_URL}${path}`, {
    ...options,
    headers: {
      'Content-Type': 'application/json',
      ...(token ? { Authorization: `Bearer ${token}` } : {}),
      ...(options.headers || {}),
    },
  });

  const raw = await response.text();
  let payload: Record<string, any> = {};
  try {
    payload = raw ? JSON.parse(raw) : {};
  } catch {
    payload = { message: raw };
  }

  if (!response.ok) {
    const detailParts: string[] = [];
    if (payload?.details?.cutoffAt) {
      detailParts.push(`إغلاق الحجز: ${payload.details.cutoffAt}`);
    }
    if (payload?.details?.tripStart) {
      detailParts.push(`موعد الرحلة: ${payload.details.tripStart}`);
    }
    if (payload?.details?.earliestStart) {
      detailParts.push(`أقرب وقت متاح: ${payload.details.earliestStart}`);
    }
    const message =
      payload.error ||
      payload.message ||
      (raw ? String(raw).slice(0, 160) : '') ||
      `فشل الطلب (${response.status})`;
    throw new Error(detailParts.length ? `${message}\n${detailParts.join('\n')}` : message);
  }
  return payload as T;
}

export function buildApiUrl(path: string) {
  return `${API_BASE_URL}${path}`;
}
