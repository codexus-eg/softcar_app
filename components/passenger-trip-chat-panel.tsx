import React from 'react';
import { Image, Pressable, StyleSheet, Text, TextInput, View } from 'react-native';

type TripChatParticipant = {
  id: string;
  name: string;
  image?: string | null;
  role?: string | null;
};

type TripChatMessage = {
  id: string;
  tripId: string;
  senderId: string;
  recipientUserId?: string | null;
  message: string;
  createdAt: string;
  sender?: TripChatParticipant | null;
  recipient?: TripChatParticipant | null;
};

type PassengerTripChatPanelProps = {
  currentUserId?: string | null;
  messages: TripChatMessage[];
  driverParticipant?: TripChatParticipant | null;
  draft: string;
  sending: boolean;
  onDraftChange: (value: string) => void;
  onSend: () => void;
};

function initials(value: string | null | undefined) {
  return String(value || '')
    .trim()
    .split(/\s+/)
    .slice(0, 2)
    .map((part) => part.charAt(0))
    .join('')
    .toUpperCase();
}

export function PassengerTripChatPanel({
  currentUserId,
  messages,
  driverParticipant,
  draft,
  sending,
  onDraftChange,
  onSend,
}: PassengerTripChatPanelProps) {
  return (
    <View style={styles.section}>
      <View style={styles.header}>
        <View style={styles.copy}>
          <Text style={styles.title}>محادثة الرحلة</Text>
          <Text style={styles.meta}>راسل السائق مباشرة من شاشة الرحلة الحالية واستقبل تحديثاته فورًا.</Text>
        </View>
        <View style={styles.badgeWrap}>
          {driverParticipant?.image ? (
            <Image source={{ uri: driverParticipant.image }} style={styles.avatarImage} />
          ) : (
            <View style={styles.avatarFallback}>
              <Text style={styles.avatarFallbackText}>{initials(driverParticipant?.name || 'D')}</Text>
            </View>
          )}
        </View>
      </View>

      {messages.length === 0 ? (
        <Text style={styles.emptyText}>لا توجد رسائل بعد. يمكنك بدء المحادثة مع السائق من هنا.</Text>
      ) : (
        <View style={styles.messageList}>
          {messages.slice(-8).map((message) => {
            const ownMessage = Boolean(currentUserId && message.senderId === currentUserId);
            const senderName = message.sender?.name || (ownMessage ? 'أنت' : 'السائق');
            return (
              <View key={message.id} style={[styles.messageBubble, ownMessage ? styles.messageBubbleOwn : styles.messageBubbleGuest]}>
                <Text style={styles.messageSender}>{senderName}</Text>
                <Text style={styles.messageBody}>{message.message}</Text>
              </View>
            );
          })}
        </View>
      )}

      <View style={styles.composer}>
        <TextInput
          value={draft}
          onChangeText={onDraftChange}
          placeholder="اكتب رسالة للسائق..."
          placeholderTextColor="#8ba6c7"
          style={styles.input}
          multiline
        />
        <Pressable
          style={[styles.sendButton, (!draft.trim() || sending) && styles.sendButtonDisabled]}
          onPress={onSend}
          disabled={!draft.trim() || sending}
        >
          <Text style={styles.sendButtonText}>{sending ? 'جارٍ الإرسال...' : 'إرسال الرسالة'}</Text>
        </Pressable>
      </View>
    </View>
  );
}

const styles = StyleSheet.create({
  section: {
    marginTop: 12,
    gap: 12,
    borderRadius: 16,
    borderWidth: 1,
    borderColor: '#21445b',
    backgroundColor: '#081322',
    padding: 14,
  },
  header: {
    flexDirection: 'row-reverse',
    alignItems: 'center',
    gap: 12,
  },
  copy: {
    flex: 1,
    gap: 4,
  },
  title: {
    color: '#f8fafc',
    fontSize: 17,
    fontWeight: '800',
    textAlign: 'right',
  },
  meta: {
    color: '#9fb5cc',
    fontSize: 12,
    lineHeight: 18,
    textAlign: 'right',
  },
  badgeWrap: {
    width: 44,
    height: 44,
    borderRadius: 16,
    overflow: 'hidden',
    backgroundColor: '#0f2238',
  },
  avatarImage: {
    width: '100%',
    height: '100%',
  },
  avatarFallback: {
    flex: 1,
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: '#D32F2F',
  },
  avatarFallbackText: {
    color: '#f8fafc',
    fontSize: 15,
    fontWeight: '900',
  },
  emptyText: {
    color: '#94a3b8',
    fontSize: 13,
    lineHeight: 20,
    textAlign: 'right',
  },
  messageList: {
    gap: 10,
  },
  messageBubble: {
    maxWidth: '92%',
    gap: 4,
    borderRadius: 18,
    paddingHorizontal: 14,
    paddingVertical: 12,
  },
  messageBubbleOwn: {
    alignSelf: 'flex-start',
    borderWidth: 1,
    borderColor: '#7dd3fc',
    backgroundColor: '#0f3b59',
  },
  messageBubbleGuest: {
    alignSelf: 'flex-end',
    borderWidth: 1,
    borderColor: '#1f3750',
    backgroundColor: '#0b1629',
  },
  messageSender: {
    color: '#c4f1e5',
    fontSize: 11,
    fontWeight: '800',
  },
  messageBody: {
    color: '#f8fafc',
    fontSize: 13,
    lineHeight: 18,
  },
  composer: {
    gap: 10,
  },
  input: {
    minHeight: 84,
    borderRadius: 16,
    borderWidth: 1,
    borderColor: '#233652',
    backgroundColor: '#081120',
    color: '#f8fafc',
    textAlign: 'right',
    textAlignVertical: 'top',
    paddingHorizontal: 14,
    paddingVertical: 14,
    fontSize: 14,
  },
  sendButton: {
    minHeight: 46,
    borderRadius: 14,
    backgroundColor: '#e2e8f0',
    alignItems: 'center',
    justifyContent: 'center',
    paddingHorizontal: 14,
  },
  sendButtonDisabled: {
    opacity: 0.5,
  },
  sendButtonText: {
    color: '#0A0A0A',
    fontSize: 13,
    fontWeight: '900',
  },
});
