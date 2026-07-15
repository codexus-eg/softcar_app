import { useEffect, useRef, useState } from 'react';
import NetInfo from '@react-native-community/netinfo';

export type ConnectivityStatus = {
  isOnline: boolean;
  connectionType: string;
  recoveredAt: number | null;
  lastChangedAt: number;
};

export function useConnectivityStatus(): ConnectivityStatus {
  const [status, setStatus] = useState<ConnectivityStatus>({
    isOnline: true,
    connectionType: 'unknown',
    recoveredAt: null,
    lastChangedAt: Date.now(),
  });
  const wasOffline = useRef(false);

  useEffect(() => {
    const update = (state: Awaited<ReturnType<typeof NetInfo.fetch>>) => {
      const isOnline = Boolean(state.isConnected && state.isInternetReachable !== false);
      const recoveredAt = isOnline && wasOffline.current ? Date.now() : null;
      wasOffline.current = !isOnline;
      setStatus((current) => {
        if (
          current.isOnline === isOnline &&
          current.connectionType === state.type &&
          recoveredAt === null
        ) {
          return current;
        }
        return {
          isOnline,
          connectionType: state.type,
          recoveredAt: recoveredAt || current.recoveredAt,
          lastChangedAt: Date.now(),
        };
      });
    };

    const unsubscribe = NetInfo.addEventListener(update);
    void NetInfo.fetch().then(update);
    return unsubscribe;
  }, []);

  return status;
}

export function useConnectivity() {
  return useConnectivityStatus().isOnline;
}
