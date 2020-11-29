import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import 'random_string.dart';

import '../utils/device_info.dart'
if (dart.library.js) '../utils/device_info_web.dart';
import '../utils/websocket.dart'
if (dart.library.js) '../utils/websocket_web.dart';
import '../utils/turn.dart' if (dart.library.js) '../utils/turn_web.dart';

enum SignalingState {
  ConnectionOpen,
  ConnectionClosed,
  ConnectionError,
}

enum CallState {
  CallStateNew,
  CallStateRinging,
  CallStateInvite,
  CallStateConnected,
  CallStateBye,
}

/*
 * callbacks for Signaling API.
 */
typedef void SignalingStateCallback(SignalingState state);
typedef void CallStateCallback(Session session, CallState state);
typedef void StreamStateCallback(Session session, MediaStream stream);
typedef void OtherEventCallback(dynamic event);
typedef void DataChannelMessageCallback(
    Session session, RTCDataChannel dc, RTCDataChannelMessage data);
typedef void DataChannelCallback(Session session, RTCDataChannel dc);

class Session {
  Session({this.sid, this.pid});
  String pid;
  String sid;
  RTCPeerConnection pc;
  RTCDataChannel dc;
  List<RTCIceCandidate> remoteCandidates = [];
}

class Signaling {
  Signaling(this._host);

  JsonEncoder _encoder = JsonEncoder();
  JsonDecoder _decoder = JsonDecoder();
  String _selfId = randomNumeric(6);
  SimpleWebSocket _socket;
  var _host;
  var _port = 8086;
  var _turnCredential;
  Map<String, Session> _sessions = {};
  MediaStream _localStream;
  List<MediaStream> _remoteStreams = <MediaStream>[];

  SignalingStateCallback onSignalingStateChange;
  CallStateCallback onCallStateChange;
  StreamStateCallback onLocalStream;
  StreamStateCallback onAddRemoteStream;
  StreamStateCallback onRemoveRemoteStream;
  OtherEventCallback onPeersUpdate;
  DataChannelMessageCallback onDataChannelMessage;
  DataChannelCallback onDataChannel;

  Map<String, dynamic> _iceServers = {
    'iceServers': [
      // {'url': 'stun:stun.l.google.com:19302'},
      //  * turn server configuration example.
      {
        'url': 'turn:127.0.0.1:3478',
        'username': 'mohsen',
        'credential': 'mohsen'
      },
    ]
  };

  final Map<String, dynamic> _config = {
    'mandatory': {},
    'optional': [
      {'DtlsSrtpKeyAgreement': true},
    ]
  };

  final Map<String, dynamic> _dcConstraints = {
    'mandatory': {
      'OfferToReceiveAudio': false,
      'OfferToReceiveVideo': false,
    },
    'optional': [],
  };

  close() async {
    await _cleanSessions();
    if (_socket != null) _socket.close();
  }

  void switchCamera() {
    if (_localStream != null) {
      _localStream.getVideoTracks()[0].switchCamera();
    }
  }

  void muteMic() {
    if (_localStream != null) {
      bool enabled = _localStream.getAudioTracks()[0].enabled;
      _localStream.getAudioTracks()[0].enabled = !enabled;
    }
  }

  void invite(String peerId, String media, bool useScreen) async {
    var sessionId = _selfId + '-' + peerId;
    Session session = await _createSession(
        peerId: peerId,
        sessionId: sessionId,
        media: media,
        screenSharing: useScreen);
    _sessions[sessionId] = session;
    if (media == 'data') {
      _createDataChannel(session);
    }
    _createOffer(session, media);
    onCallStateChange?.call(session, CallState.CallStateNew);
  }

  void bye(String sessionId) {
    _send('bye', {
      'session_id': sessionId,
      'from': _selfId,
    });

    _closeSession(_sessions[sessionId]);
  }

  void onMessage(message) async {
    Map<String, dynamic> mapData = message;
    var data = mapData['data'];

    switch (mapData['type']) {
      case 'peers':
        {
          List<dynamic> peers = data;
          if (onPeersUpdate != null) {
            Map<String, dynamic> event = Map<String, dynamic>();
            event['self'] = _selfId;
            event['peers'] = peers;
            onPeersUpdate?.call(event);
          }
        }
        break;
      case 'offer':
        {
          var peerId = data['from'];
          var description = data['description'];
          var media = data['media'];
          var sessionId = data['session_id'];
          var session = _sessions[sessionId];
          var newSession = await _createSession(
              session: session,
              peerId: peerId,
              sessionId: sessionId,
              media: media,
              screenSharing: false);
          _sessions[sessionId] = newSession;
          await newSession.pc.setRemoteDescription(
              RTCSessionDescription(description['sdp'], description['type']));
          await _createAnswer(newSession, media);
          if (newSession.remoteCandidates.length > 0) {
            newSession.remoteCandidates.forEach((candidate) async {
              await newSession.pc.addCandidate(candidate);
            });
            newSession.remoteCandidates.clear();
          }
          onCallStateChange?.call(newSession, CallState.CallStateNew);
        }
        break;
      case 'answer':
        {
          var description = data['description'];
          var sessionId = data['session_id'];
          var session = _sessions[sessionId];
          session?.pc?.setRemoteDescription(
              RTCSessionDescription(description['sdp'], description['type']));
        }
        break;
      case 'candidate':
        {
          var peerId = data['from'];
          var candidateMap = data['candidate'];
          var sessionId = data['session_id'];
          var session = _sessions[sessionId];
          RTCIceCandidate candidate = RTCIceCandidate(candidateMap['candidate'],
              candidateMap['sdpMid'], candidateMap['sdpMLineIndex']);

          if (session != null) {
            if (session.pc != null) {
              await session.pc.addCandidate(candidate);
            } else {
              session.remoteCandidates.add(candidate);
            }
          } else {
            _sessions[sessionId] = Session(pid: peerId, sid: sessionId)
              ..remoteCandidates.add(candidate);
          }
        }
        break;
      case 'leave':
        {
          var peerId = data as String;
          _closeSessionByPeerId(peerId);
        }
        break;
      case 'bye':
        {
          var sessionId = data['session_id'];
          print('bye: ' + sessionId);
          var session = _sessions.remove(sessionId);
          onCallStateChange?.call(session, CallState.CallStateBye);
          _closeSession(session);
        }
        break;
      case 'keepalive':
        {
          print('keepalive response!');
        }
        break;
      default:
        break;
    }
  }

  Future<void> connect() async {
    var url = 'https://$_host:$_port/ws';
    _socket = SimpleWebSocket(url);

    print('connect to $url');

    // if (_turnCredential == null) {
    //   try {
    //     _turnCredential = await getTurnCredential(_host, _port);
    //     debugPrint('tuen credentials: $_turnCredential');
        /*{
            "username": "1584195784:mbzrxpgjys",
            "password": "isyl6FF6nqMTB9/ig5MrMRUXqZg",
            "ttl": 86400,
            "uris": ["turn:127.0.0.1:19302?transport=udp"]
          }
        */
        /*_iceServers = {
          'iceServers': [
            {
              'urls': _turnCredential['uris'][0],
              'username': _turnCredential['username'],
              'credential': _turnCredential['password']
            },
          ]
        };*/
        _iceServers = {
          'iceServers': [
            {
              'urls': 'turn:127.0.0.1:3478',
              'username': 'mohsen',
              'credential': 'mohsen',
            },
          ]
        };
    //   } catch (e) {}
    // }

    _socket.onOpen = () {
      print('onOpen');
      onSignalingStateChange?.call(SignalingState.ConnectionOpen);
      _send('new', {
        'name': DeviceInfo.label,
        'id': _selfId,
        'user_agent': DeviceInfo.userAgent
      });
    };

    _socket.onMessage = (message) {
      print('Received data: ' + message);
      onMessage(_decoder.convert(message));
    };

    _socket.onClose = (int code, String reason) {
      print('Closed by server [$code => $reason]!');
      onSignalingStateChange?.call(SignalingState.ConnectionClosed);
    };

    await _socket.connect();
  }

  Future<MediaStream> createStream(String media, bool userScreen) async {
    final Map<String, dynamic> mediaConstraints = {
      'audio': true,
      'video': {
        'mandatory': {
          'minWidth':
          '640', // Provide your own width, height and frame rate here
          'minHeight': '480',
          'minFrameRate': '30',
        },
        'facingMode': 'user',
        'optional': [],
      }
    };

    MediaStream stream = userScreen
        ? await navigator.mediaDevices.getDisplayMedia(mediaConstraints)
        : await navigator.mediaDevices.getUserMedia(mediaConstraints);
    onLocalStream?.call(null, stream);
    return stream;
  }

  Future<Session> _createSession(
      {Session session,
        String peerId,
        String sessionId,
        String media,
        bool screenSharing}) async {
    var newSession = session ?? Session(sid: sessionId, pid: peerId);
    if (media != 'data')
      _localStream = await createStream(media, screenSharing);
    print(_iceServers);
    RTCPeerConnection pc = await createPeerConnection({
      ..._iceServers,
      ...{'sdpSemantics': 'unified-plan'}
    }, _config);
    if (media != 'data') {
      _localStream
          .getTracks()
          .forEach((track) async => await pc.addTrack(track, _localStream));

      // Unified-Plan: Simuclast
      /*
      await pc.addTransceiver(
        track: _localStream.getAudioTracks()[0],
        init: RTCRtpTransceiverInit(
            direction: TransceiverDirection.SendOnly, streams: [_localStream]),
      );

      await pc.addTransceiver(
        track: _localStream.getVideoTracks()[0],
        init: RTCRtpTransceiverInit(
            direction: TransceiverDirection.SendOnly,
            streams: [
              _localStream
            ],
            sendEncodings: [
              RTCRtpEncoding(rid: 'f', active: true),
              RTCRtpEncoding(
                rid: 'h',
                active: true,
                scaleResolutionDownBy: 2.0,
                maxBitrate: 150000,
              ),
              RTCRtpEncoding(
                rid: 'q',
                active: true,
                scaleResolutionDownBy: 4.0,
                maxBitrate: 100000,
              ),
            ]),
      );*/
      /*
        var sender = pc.getSenders().find(s => s.track.kind == "video");
        var parameters = sender.getParameters();
        if(!parameters)
          parameters = {};
        parameters.encodings = [
          { rid: "h", active: true, maxBitrate: 900000 },
          { rid: "m", active: true, maxBitrate: 300000, scaleResolutionDownBy: 2 },
          { rid: "l", active: true, maxBitrate: 100000, scaleResolutionDownBy: 4 }
        ];
        sender.setParameters(parameters);
      */
    }
    pc.onIceCandidate = (candidate) {
      if (candidate == null) {
        print('onIceCandidate: complete!');
        return;
      }
      _send('candidate', {
        'to': peerId,
        'from': _selfId,
        'candidate': {
          'sdpMLineIndex': candidate.sdpMlineIndex,
          'sdpMid': candidate.sdpMid,
          'candidate': candidate.candidate,
        },
        'session_id': sessionId,
      });
    };

    pc.onIceConnectionState = (state) {};

    //pc.onAddStream = (stream) {
    //  onAddRemoteStream?.call(stream);
    //  _remoteStreams.add(stream);
    //};

    // Unified-Plan
    pc.onTrack = (event) {
      if (event.track.kind == 'video') {
        onAddRemoteStream?.call(newSession, event.streams[0]);
      }
    };

    pc.onRemoveStream = (stream) {
      onRemoveRemoteStream?.call(newSession, stream);
      _remoteStreams.removeWhere((it) {
        return (it.id == stream.id);
      });
    };

    pc.onDataChannel = (channel) {
      _addDataChannel(newSession, channel);
    };

    newSession.pc = pc;
    return newSession;
  }

  void _addDataChannel(Session session, RTCDataChannel channel) {
    channel.onDataChannelState = (e) {};
    channel.onMessage = (RTCDataChannelMessage data) {
      onDataChannelMessage?.call(session, channel, data);
    };
    session.dc = channel;
    onDataChannel?.call(session, channel);
  }

  Future<void> _createDataChannel(Session session,
      {label: 'fileTransfer'}) async {
    RTCDataChannelInit dataChannelDict = RTCDataChannelInit()
      ..maxRetransmits = 30;
    RTCDataChannel channel =
    await session.pc.createDataChannel(label, dataChannelDict);
    _addDataChannel(session, channel);
  }

  Future<void> _createOffer(Session session, String media) async {
    try {
      RTCSessionDescription s =
      await session.pc.createOffer(media == 'data' ? _dcConstraints : {});
      await session.pc.setLocalDescription(s);
      _send('offer', {
        'to': session.pid,
        'from': _selfId,
        'description': {'sdp': s.sdp, 'type': s.type},
        'session_id': session.sid,
        'media': media,
      });
    } catch (e) {
      print(e.toString());
    }
  }

  Future<void> _createAnswer(Session session, String media) async {
    try {
      RTCSessionDescription s =
      await session.pc.createAnswer(media == 'data' ? _dcConstraints : {});
      await session.pc.setLocalDescription(s);
      _send('answer', {
        'to': session.pid,
        'from': _selfId,
        'description': {'sdp': s.sdp, 'type': s.type},
        'session_id': session.sid,
      });
    } catch (e) {
      print(e.toString());
    }
  }

  _send(event, data) {
    var request = Map();
    request["type"] = event;
    request["data"] = data;
    _socket.send(_encoder.convert(request));
  }

  Future<void> _cleanSessions() async {
    if (_localStream != null) {
      _localStream.getTracks().forEach((element) async {
        await element.dispose();
      });
      await _localStream.dispose();
      _localStream = null;
    }
    _sessions.forEach((key, sess) async {
      await sess?.pc?.close();
      await sess?.dc?.close();
    });
    _sessions.clear();
  }

  void _closeSessionByPeerId(String peerId) {
    var session;
    _sessions.removeWhere((String key, Session sess) {
      var ids = key.split('-');
      session = sess;
      return peerId == ids[0] || peerId == ids[1];
    });
    if (session != null) {
      _closeSession(session);
      onCallStateChange?.call(session, CallState.CallStateBye);
    }
  }

  Future<void> _closeSession(Session session) async {
    _localStream?.getTracks()?.forEach((element) async {
      await element.dispose();
    });
    await _localStream?.dispose();
    _localStream = null;

    await session?.pc?.close();
    await session?.dc?.close();
  }
}
