import React, { useEffect, useState } from 'react';
import { ActivityIndicator, Alert, Pressable, StyleSheet, Text, View } from 'react-native';
import * as FileSystem from 'expo-file-system/legacy';
import * as Sharing from 'expo-sharing';
import { apiRequest } from '../utils/api-client';

type MobileSession = {
  id: string;
  deviceName?: string | null;
  platform?: string | null;
  expiresAt: string;
  lastUsedAt: string;
  createdAt: string;
  current: boolean;
};

export function AccountSecurityPanel({ token }: { token: string }) {
  const [sessions, setSessions] = useState<MobileSession[]>([]);
  const [loading, setLoading] = useState(true);
  const [busyId, setBusyId] = useState('');
  const [exporting, setExporting] = useState(false);

  async function loadSessions() {
    setLoading(true);
    try {
      const payload = await apiRequest<{ sessions: MobileSession[] }>('/api/mobile/sessions', token);
      setSessions(payload.sessions || []);
    } catch (error) {
      Alert.alert('تعذر تحميل الأجهزة', error instanceof Error ? error.message : 'حاول مرة أخرى.');
    } finally {
      setLoading(false);
    }
  }

  useEffect(() => {
    void loadSessions();
  }, [token]);

  async function revokeSession(sessionId: string) {
    setBusyId(sessionId);
    try {
      await apiRequest('/api/mobile/sessions', token, {
        method: 'DELETE',
        body: JSON.stringify({ sessionId }),
      });
      setSessions((current) => current.filter((session) => session.id !== sessionId));
    } catch (error) {
      Alert.alert('تعذر إنهاء الجلسة', error instanceof Error ? error.message : 'حاول مرة أخرى.');
    } finally {
      setBusyId('');
    }
  }

  async function revokeOtherSessions() {
    setBusyId('others');
    try {
      await apiRequest('/api/mobile/sessions', token, {
        method: 'DELETE',
        body: JSON.stringify({ allOtherSessions: true }),
      });
      setSessions((current) => current.filter((session) => session.current));
      Alert.alert('تم تأمين الحساب', 'تم تسجيل الخروج من كل الأجهزة الأخرى.');
    } catch (error) {
      Alert.alert('تعذر إنهاء الجلسات', error instanceof Error ? error.message : 'حاول مرة أخرى.');
    } finally {
      setBusyId('');
    }
  }

  async function exportAccount() {
    setExporting(true);
    try {
      const payload = await apiRequest<Record<string, unknown>>('/api/mobile/account/export', token);
      const directory = FileSystem.cacheDirectory || FileSystem.documentDirectory;
      if (!directory) throw new Error('مساحة حفظ الملفات غير متاحة.');
      const fileUri = `${directory}softcar-account-${Date.now()}.json`;
      await FileSystem.writeAsStringAsync(fileUri, JSON.stringify(payload, null, 2), {
        encoding: FileSystem.EncodingType.UTF8,
      });
      if (!(await Sharing.isAvailableAsync())) throw new Error('مشاركة الملفات غير متاحة على هذا الجهاز.');
      await Sharing.shareAsync(fileUri, {
        mimeType: 'application/json',
        dialogTitle: 'تصدير بيانات حساب سوفت كار',
      });
    } catch (error) {
      Alert.alert('تعذر تصدير البيانات', error instanceof Error ? error.message : 'حاول مرة أخرى.');
    } finally {
      setExporting(false);
    }
  }

  return (
    <View style={styles.panel}>
      <View style={styles.header}>
        <View style={styles.flex}>
          <Text style={styles.title}>الأجهزة وأمان الحساب</Text>
          <Text style={styles.hint}>راجع كل جلسة مسجلة وأنهِ أي جهاز لا تعرفه.</Text>
        </View>
        <Pressable style={styles.smallButton} onPress={() => void loadSessions()} disabled={loading}>
          <Text style={styles.smallButtonText}>تحديث</Text>
        </Pressable>
      </View>

      {loading ? <ActivityIndicator color="#D32F2F" /> : null}
      {!loading && sessions.length === 0 ? <Text style={styles.empty}>لا توجد جلسات نشطة.</Text> : null}
      {sessions.map((session) => (
        <View key={session.id} style={styles.session}>
          <View style={styles.flex}>
            <Text style={styles.sessionTitle}>{session.deviceName || 'جهاز محمول'}</Text>
            <Text style={styles.meta}>{session.platform || 'تطبيق'} | آخر استخدام {new Date(session.lastUsedAt).toLocaleString('ar-EG')}</Text>
          </View>
          {session.current ? (
            <Text style={styles.current}>هذا الجهاز</Text>
          ) : (
            <Pressable style={styles.dangerButton} onPress={() => void revokeSession(session.id)} disabled={Boolean(busyId)}>
              <Text style={styles.dangerText}>{busyId === session.id ? 'جارٍ الإنهاء' : 'إنهاء'}</Text>
            </Pressable>
          )}
        </View>
      ))}

      <View style={styles.actions}>
        <Pressable style={styles.secondaryButton} onPress={() => void revokeOtherSessions()} disabled={Boolean(busyId)}>
          <Text style={styles.secondaryText}>{busyId === 'others' ? 'جارٍ التأمين...' : 'إنهاء الأجهزة الأخرى'}</Text>
        </Pressable>
        <Pressable style={styles.primaryButton} onPress={() => void exportAccount()} disabled={exporting}>
          <Text style={styles.primaryText}>{exporting ? 'جارٍ التصدير...' : 'تصدير بياناتي'}</Text>
        </Pressable>
      </View>
    </View>
  );
}

const styles = StyleSheet.create({
  panel: { marginTop: 14, gap: 10, padding: 14, borderWidth: 1, borderColor: '#283548', backgroundColor: '#0A0A0A', borderRadius: 8 },
  header: { flexDirection: 'row-reverse', alignItems: 'center', gap: 10 },
  flex: { flex: 1 },
  title: { color: '#FFFFFF', fontSize: 16, fontWeight: '900', textAlign: 'right' },
  hint: { color: '#9CA3AF', fontSize: 12, marginTop: 4, textAlign: 'right' },
  smallButton: { paddingHorizontal: 12, paddingVertical: 8, borderWidth: 1, borderColor: '#4B5563', borderRadius: 7 },
  smallButtonText: { color: '#FFFFFF', fontWeight: '800' },
  empty: { color: '#9CA3AF', textAlign: 'center', padding: 10 },
  session: { flexDirection: 'row-reverse', alignItems: 'center', gap: 10, padding: 12, borderWidth: 1, borderColor: '#1F2937', borderRadius: 7 },
  sessionTitle: { color: '#FFFFFF', fontWeight: '800', textAlign: 'right' },
  meta: { color: '#9CA3AF', fontSize: 11, marginTop: 3, textAlign: 'right' },
  current: { color: '#86EFAC', fontSize: 11, fontWeight: '900' },
  dangerButton: { paddingHorizontal: 12, paddingVertical: 8, borderWidth: 1, borderColor: '#7F1D1D', backgroundColor: '#2A0D0D', borderRadius: 7 },
  dangerText: { color: '#FCA5A5', fontWeight: '900' },
  actions: { flexDirection: 'row-reverse', gap: 8 },
  secondaryButton: { flex: 1, minHeight: 44, alignItems: 'center', justifyContent: 'center', borderWidth: 1, borderColor: '#4B5563', borderRadius: 7 },
  secondaryText: { color: '#FFFFFF', fontWeight: '800', textAlign: 'center' },
  primaryButton: { flex: 1, minHeight: 44, alignItems: 'center', justifyContent: 'center', backgroundColor: '#D32F2F', borderRadius: 7 },
  primaryText: { color: '#FFFFFF', fontWeight: '900', textAlign: 'center' },
});
