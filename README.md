# Flutter WebRTC Client
WebRTC client for Android, IOS and web browsers written by Flutter.

based on [this repository](https://github.com/flutter-webrtc/flutter-webrtc).

## Server
You need two servers, Signaling server and Turn/Stun Server

### Signaling Server

Use this repository: [flutter_webrtc_server](https://github.com/flutter-webrtc/flutter-webrtc-server)

### Turn Server
For turn server use this link: [coturn server install](https://nextcloud-talk.readthedocs.io/en/latest/TURN/)

## Config

### Config coturn server
By using the above link, config the coturn.
 - if you want to use coturn and signaling server in the same machine, use this config in /etc/turnserver.conf
 
```
realm=coturn.meetrix.io
fingerprint
listening-ip=0.0.0.0
external-ip=127.0.0.1
listening-port=3478
min-port=10000
max-port=20000
log-file=/var/log/turnserver.log
verbose

user=my_username:my_password
lt-cred-mech
```
 - otherwise, use your server's IP in 'external-ip'
 
 ### config Signaling server
  - make these changes in flutter_webrtc_server/configs/config.ini
```
[turn]
public_ip=127.0.0.1
port=19302
realm=coturn.meetrix.io
```
 - Use your TURN server's public IP above (if not localhost).
 
 ### Changing the project code
 - in src/signaling.dart where there is this code
 ```
 _iceServers = {
          'iceServers': [
            {
              'urls': 'turn:127.0.0.1:3478',
              'username': 'mohsen',
              'credential': 'mohsen',
            },
          ]
        };
 ```
 - change it to your turn server's IP and use the username & password you set here ![Config coturn server](#config-coturn-server).
    - When both servers are local, use the IP of TURN server, seen by Signaling server. 
