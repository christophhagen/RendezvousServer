# Rendezvous server

Rendezvous is a system aimed at providing end-to-end encrypted communication and data sharing, which can be federated between many servers. Users can register with a server of their choice, or create their own. Servers don't have access to the data exchanged between clients, which is organized in `Topics`. Multi-device support and optional push notifications allow modern messaging.

# Disclaimer

THIS IS A PRIVATE PROJECT STILL VERY MUCH UNDER DEVELOPMENT. MAYBE DON'T USE THIS YET.

## Aims

### Functions

Provide topic-based communication between multiple users. Topics are similar to groups and provide:
- Persistent storage of all exchanged messages (Losing a device doesn't mean the data is lost)
- End-to-end encryption (the server can't read the data)
- Optional backward secrecy (new members can't read old messages)
- Topics can be shared read-only with topic members.
- Topics provide a cryptographic log, which prevents the server or other users from retroactively omitting or adding messages.

### Devices

Provide multi-device support for each user.
- Users can have many devices, which can all participate in topics.
- Support for push notifications of new content.
- Adding new devices should be easy
- Deletion of devices should be possible.
- No information about devices is leaked to other topic members.

### Security

Provide strong cryptographic guarantees.
- All data in topics is end-to-end encrypted.
- Only secure ciphers and other primitives are used.
- A cryptographic log ensures that the message chain can't be tampered with.
- Compromise of long-term identity keys doesn't compromise individual topics (forward secrecy).
- The origin of each message is verifiable.

### Efficiency

Provide efficient and fast communication.
- Messages are encrypted once for all topic members.
- Message overhead is small.
- Changes to topics are small (depending on the number of members).
- Encryption of messages is symmetric and fast.


## Keys

The Rendezvous encryption scheme consists of several different key types.

### New users

New users create a long-term secret, their `Identity Key`, and register it with a server of their choice. The server owner allows users to register by providing one-time registration pins.

### Devices

Each device creates an individual `Device Key`, which is registered on the server by signing a request with the `Identity Key`. The `Identity Key` is transmitted out-of-band to new devices during the initialization phase (e.g. by scanning a QR code from an existing device).

### Device prekeys

Each device provides random `Device Pre Keys` to the server, which are signed by the `Device Key`, and used to provide forward secrecy for key exchanges.

### Topic keys

Each `Device Pre Key` is used once to distribute a `Topic Key` to all devices of a user. A `Topic Key` is signed by the `Identity Key` of a user, and a new `Topic Key` is used for each topic to provide forward secrecy. `Topic Keys` consist of a `Topic Signature Key` (used to sign messages in a topic) and a `Topic Encryption Key` (used to decrypt topic updates).

When a new device is registered for a user, the topic keys are transmitted out of band to the new device (e.g. by scanning a QR code).

### Topic creation

When a new topic is created, the topic creator collects a `Topic Key` for each member of the topic, and uses these to encrypt the random `Message Key`.

### Topic changes

If a new member is added by the topic administrator, then the `Message Key` is sent to the member using a `Topic Key`. If users leave a group, then a new `Message Key` is created by the administrator and delivered to each remaining member using their `Topic Key`.

### Messages

The `Message Key` is used to encrypt all messages in the group, and each message is signed by the sender using the `Topic Key` to provide attribution and to ensure that only members with the correct permissions can post to a group. This access control is enforced by the server hosting the topic, and is validated by all members when they receive new messages.

Each message is authenticated by the `Message Tag`, which is computed with the `Message Key` and ensures its integrity. Each sender signs the messages it sends, which are verified by both server and other clients. The server responsible for the topic appends all `Message Tags` to a tamper-proof log, which ensures topic consistency between members and prevents the server or other users from retroactively adding or removing messages.
