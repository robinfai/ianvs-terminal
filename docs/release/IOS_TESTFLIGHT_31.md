# TestFlight 0.1.0 (31)

- SSH sessions no longer disconnect because of idle time or missed keepalive replies. Existing profiles and ProxyJump hops use the same persistent policy. Setup, authentication and host-key prompts use an overflow-safe 100-year deadline, while manual cancellation and server/transport failures remain effective.
- Keepalive interval remains configurable (0 disables heartbeat transmission); it is not increased to an impractically long interval. Legacy connect-timeout and retry-count fields remain in stored profiles for compatibility but are superseded by the runtime policy; the editor displays the effective policy as read-only text.
- SFTP request, forwarding handshake and shutdown-cleanup limits remain bounded: those protect individual operations and do not impose an idle lifetime on SSH sessions.
- iOS filled buttons use white text/icons with a deeper blue surface in light and dark themes. This fixes the black content still present in build 30.
- iOS suspension/termination, server policy and actual network failures can still end connections; this is not a promise of unlimited iOS background execution.

Distribution: do not distribute in France. Validation: 46 native SSH tests and 40 Flutter SSH/theme/iOS tests passed; targeted Flutter analysis passed. iOS button rendering was checked on the iOS 27.0 simulator. Other supported OS versions have not been visually revalidated. Publication is pending.
