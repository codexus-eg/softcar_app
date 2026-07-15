import React, { useEffect, useMemo, useState } from 'react';
import { ActivityIndicator, Alert, Pressable, StyleSheet, Text, TextInput, View } from 'react-native';
import { apiRequest } from '../utils/api-client';

type SupportChatMessage = {
  id: string;
  message: string;
  createdAt: string;
  sender: { id: string; name: string; role: string } | null;
};

type SupportChatSession = {
  id: string;
  lane: 'CUSTOMER_SERVICE' | 'TECHNICAL_SUPPORT';
  status: 'QUEUED' | 'ACTIVE' | 'RESOLVED' | 'CLOSED';
  subject: string;
  assignedTo: { id: string; name: string } | null;
  messages: SupportChatMessage[];
  updatedAt: string;
};

export function SupportChatPanel({ token, userId }: { token: string; userId?: string | null }) {
  const [sessions, setSessions] = useState<SupportChatSession[]>([]);
  const [queuePosition, setQueuePosition] = useState<number | null>(null);
  const [subject, setSubject] = useState('');
  const [message, setMessage] = useState('');
  const [lane, setLane] = useState<'CUSTOMER_SERVICE' | 'TECHNICAL_SUPPORT'>('CUSTOMER_SERVICE');
  const [loading, setLoading] = useState(true);
  const [sending, setSending] = useState(false);
  const activeSession = useMemo(
    () => sessions.find((session) => ['QUEUED', 'ACTIVE'].includes(session.status)) || sessions[0] || null,
    [sessions]
  );

  async function loadChats(silent = false) {
    if (!silent) setLoading(true);
    try {
      const payload = await apiRequest<{ sessions: SupportChatSession[]; queuePosition: number | null }>('/api/mobile/support-chat', token);
      setSessions(payload.sessions || []);
      setQueuePosition(payload.queuePosition);
    } catch (error) {
      if (!silent) Alert.alert('تعذر تحميل الدردشة', error instanceof Error ? error.message : 'حاول مرة أخرى.');
    } finally {
      if (!silent) setLoading(false);
    }
  }

  useEffect(() => {
    void loadChats();
    const interval = setInterval(() => void loadChats(true), 10000);
    return () => clearInterval(interval);
  }, [token]);

  async function createChat() {
    if (subject.trim().length < 3 || message.trim().length < 2) {
      Alert.alert('أكمل بيانات الدردشة', 'اكتب عنوانًا واضحًا ورسالة قصيرة على الأقل.');
      return;
    }
    setSending(true);
    try {
      await apiRequest('/api/mobile/support-chat', token, {
        method: 'POST',
        body: JSON.stringify({ action: 'create', subject: subject.trim(), message: message.trim(), lane }),
      });
      setSubject('');
      setMessage('');
      await loadChats(true);
    } catch (error) {
      Alert.alert('تعذر بدء الدردشة', error instanceof Error ? error.message : 'حاول مرة أخرى.');
    } finally {
      setSending(false);
    }
  }

  async function sendMessage() {
    if (!activeSession || !message.trim()) return;
    setSending(true);
    try {
      await apiRequest('/api/mobile/support-chat', token, {
        method: 'POST',
        body: JSON.stringify({ action: 'message', sessionId: activeSession.id, message: message.trim() }),
      });
      setMessage('');
      await loadChats(true);
    } catch (error) {
      Alert.alert('تعذر إرسال الرسالة', error instanceof Error ? error.message : 'حاول مرة أخرى.');
    } finally {
      setSending(false);
    }
  }

  async function closeChat() {
    if (!activeSession) return;
    await apiRequest('/api/mobile/support-chat', token, {
      method: 'POST',
      body: JSON.stringify({ action: 'close', sessionId: activeSession.id }),
    });
    await loadChats(true);
  }

  return (
    <View style={styles.panel}>
      <View style={styles.header}>
        <View style={styles.flex}>
          <Text style={styles.title}>الدردشة المباشرة مع الدعم</Text>
          <Text style={styles.hint}>تدخل الدردشة قائمة الانتظار الحقيقية ويظهر الموظف المسؤول عند استلامها.</Text>
        </View>
        {activeSession ? <Text style={styles.status}>{activeSession.status === 'QUEUED' ? `انتظار ${queuePosition || 1}` : activeSession.status === 'ACTIVE' ? 'نشطة' : 'مغلقة'}</Text> : null}
      </View>

      {loading ? <ActivityIndicator color="#D32F2F" /> : null}
      {activeSession ? (
        <>
          <Text style={styles.subject}>{activeSession.subject}</Text>
          <View style={styles.messages}>
            {activeSession.messages.slice(-12).map((item) => {
              const mine = item.sender?.id === userId;
              return (
                <View key={item.id} style={[styles.bubble, mine ? styles.mine : styles.theirs]}>
                  <Text style={styles.messageText}>{item.message}</Text>
                  <Text style={styles.messageMeta}>{mine ? 'أنت' : item.sender?.name || 'الدعم'} | {new Date(item.createdAt).toLocaleTimeString('ar-EG', { hour: '2-digit', minute: '2-digit' })}</Text>
                </View>
              );
            })}
          </View>
          {['QUEUED', 'ACTIVE'].includes(activeSession.status) ? (
            <>
              <TextInput value={message} onChangeText={setMessage} placeholder="اكتب رسالتك..." placeholderTextColor="#6B7280" multiline style={styles.input} />
              <View style={styles.actions}>
                <Pressable style={styles.secondary} onPress={() => void closeChat()}>
                  <Text style={styles.secondaryText}>إنهاء الدردشة</Text>
                </Pressable>
                <Pressable style={styles.primary} onPress={() => void sendMessage()} disabled={sending || !message.trim()}>
                  <Text style={styles.primaryText}>{sending ? 'جارٍ الإرسال...' : 'إرسال'}</Text>
                </Pressable>
              </View>
            </>
          ) : null}
        </>
      ) : !loading ? (
        <>
          <View style={styles.lanes}>
            {([
              ['CUSTOMER_SERVICE', 'خدمة العملاء'],
              ['TECHNICAL_SUPPORT', 'الدعم الفني'],
            ] as const).map(([value, label]) => (
              <Pressable key={value} style={[styles.lane, lane === value && styles.laneActive]} onPress={() => setLane(value)}>
                <Text style={[styles.laneText, lane === value && styles.laneTextActive]}>{label}</Text>
              </Pressable>
            ))}
          </View>
          <TextInput value={subject} onChangeText={setSubject} placeholder="عنوان الطلب" placeholderTextColor="#6B7280" style={styles.input} />
          <TextInput value={message} onChangeText={setMessage} placeholder="اشرح ما تحتاج إليه..." placeholderTextColor="#6B7280" multiline style={[styles.input, styles.textArea]} />
          <Pressable style={styles.primary} onPress={() => void createChat()} disabled={sending}>
            <Text style={styles.primaryText}>{sending ? 'جارٍ فتح الدردشة...' : 'بدء الدردشة'}</Text>
          </Pressable>
        </>
      ) : null}
    </View>
  );
}

const styles = StyleSheet.create({
  panel: { gap: 10, padding: 14, borderWidth: 1, borderColor: '#283548', backgroundColor: '#0A0A0A', borderRadius: 8 },
  header: { flexDirection: 'row-reverse', alignItems: 'center', gap: 10 },
  flex: { flex: 1 },
  title: { color: '#FFFFFF', fontSize: 16, fontWeight: '900', textAlign: 'right' },
  hint: { color: '#9CA3AF', fontSize: 12, marginTop: 4, textAlign: 'right' },
  status: { color: '#FFFFFF', backgroundColor: '#7F1D1D', paddingHorizontal: 10, paddingVertical: 6, borderRadius: 7, fontSize: 11, fontWeight: '900' },
  subject: { color: '#FCA5A5', fontWeight: '900', textAlign: 'right' },
  messages: { gap: 7 },
  bubble: { maxWidth: '90%', padding: 10, borderRadius: 8 },
  mine: { alignSelf: 'flex-start', backgroundColor: '#3B1111' },
  theirs: { alignSelf: 'flex-end', backgroundColor: '#172033' },
  messageText: { color: '#FFFFFF', textAlign: 'right', lineHeight: 20 },
  messageMeta: { color: '#9CA3AF', fontSize: 10, marginTop: 5, textAlign: 'right' },
  input: { minHeight: 46, color: '#FFFFFF', textAlign: 'right', borderWidth: 1, borderColor: '#374151', backgroundColor: '#111318', borderRadius: 7, paddingHorizontal: 12, paddingVertical: 10 },
  textArea: { minHeight: 90, textAlignVertical: 'top' },
  actions: { flexDirection: 'row-reverse', gap: 8 },
  primary: { flex: 1, minHeight: 46, alignItems: 'center', justifyContent: 'center', backgroundColor: '#D32F2F', borderRadius: 7 },
  primaryText: { color: '#FFFFFF', fontWeight: '900' },
  secondary: { flex: 1, minHeight: 46, alignItems: 'center', justifyContent: 'center', borderWidth: 1, borderColor: '#4B5563', borderRadius: 7 },
  secondaryText: { color: '#FFFFFF', fontWeight: '800' },
  lanes: { flexDirection: 'row-reverse', gap: 8 },
  lane: { flex: 1, padding: 10, borderWidth: 1, borderColor: '#374151', borderRadius: 7 },
  laneActive: { borderColor: '#D32F2F', backgroundColor: '#2A0D0D' },
  laneText: { color: '#9CA3AF', textAlign: 'center', fontWeight: '800' },
  laneTextActive: { color: '#FFFFFF' },
});
