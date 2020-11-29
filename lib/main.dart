import 'dart:core';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'src/call_sample/call_sample.dart';
import 'src/call_sample/data_channel_sample.dart';
import 'src/route_item.dart';

void main() => runApp(new MyApp());

class MyApp extends StatefulWidget {
  @override
  _MyAppState createState() => new _MyAppState();
}

enum DialogDemoAction {
  cancel,
  connect,
}

class _MyAppState extends State<MyApp> {
  List<RouteItem> items;
  String _server = '';
  SharedPreferences _prefs;
  List<Server> servers;
  TextEditingController controllerName;
  TextEditingController controllerIP;

  bool _datachannel = false;

  @override
  initState() {
    super.initState();
    _initData();
    _initItems();
    controllerName = TextEditingController();
    controllerIP = TextEditingController();
  }

  _buildRow(context, item) {
    return ListBody(children: <Widget>[
      ListTile(
        title: Text(item.title),
        onTap: () => item.push(context),
        trailing: Icon(Icons.arrow_right),
      ),
      Divider()
    ]);
  }

  Future<void> addServer(Server server) async {
    String lst = _prefs.getString('servers');
    if (lst == null) {
      lst = server.name + ":" + server.address + ",";
    } else {
      lst += server.name + ":" + server.address + ",";
    }

    print(lst);

    await _prefs.setString('servers', lst);
    setState(() {
      servers = getServers();
    });
  }

  showDialogAddServer() {
    showDialog(
      context: _scaffoldKey.currentContext,
      builder: (context) {
        return AlertDialog(
          title: Text('Add server'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.start,
            children: [
              TextField(
                controller: controllerName,
                decoration: InputDecoration(hintText: 'Server Name'),
              ),
              TextField(
                controller: controllerIP,
                decoration: InputDecoration(hintText: 'Server hostname/IP'),
              )
            ],
          ),
          actions: [
            RaisedButton(
              onPressed: () {
                addServer(Server(controllerName.text, controllerIP.text));
                controllerIP.clear();
                controllerName.clear();
                Navigator.pop(context);
              },
              child: Text('Add'),
            )
          ],
        );
      },
    );
  }

  var _scaffoldKey = new GlobalKey<ScaffoldState>();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(),
      home: Scaffold(
          key: _scaffoldKey,
          floatingActionButton: RaisedButton(
            onPressed: () {
              showDialogAddServer();
            },
            child: Text(
              'Add Server',
              style: TextStyle(fontSize: 18.0),
            ),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20.0)),
          ),
          appBar: AppBar(
              title: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Signaling Servers',
              ),
              IconButton(
                onPressed: () {
                  if (_prefs != null) {
                    setState(() {
                      servers = getServers();
                    });
                  }
                },
                icon: Icon(Icons.refresh),
              )
            ],
          )),
          /*body: ListView.builder(
              padding: const EdgeInsets.all(0.0),
              itemCount: items.length,
              itemBuilder: (context, i) {
                return _buildRow(context, items[i]);
              })),*/
          body: (servers != null && servers.length != 0)
              ? ListView.builder(
                  itemCount: servers.length,
                  itemBuilder: (context, i) {
                    return ListTile(
                      title: Text(servers[i].name),
                      subtitle: Text(servers[i].address),
                      onTap: () {
                        showDialog(
                            context: context,
                            builder: (context) {
                              return AlertDialog(
                                title: Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(servers[i].name),
                                    IconButton(
                                      icon: Icon(Icons.close),
                                      onPressed: () {
                                        Navigator.pop(context);
                                      },
                                    )
                                  ],
                                ),
                                content: RaisedButton(
                                  onPressed: () {
                                    Navigator.pushReplacement(
                                        context,
                                        MaterialPageRoute(
                                            builder: (BuildContext context) =>
                                                CallPage(
                                                    host: servers[i].address)));
                                  },
                                  child: Text('Enter Calling room'),
                                ),
                              );
                            });
                      },
                    );
                  },
                )
              : Center(
                  child: Text(
                  'No Servers',
                  style: TextStyle(fontSize: 20.0),
                ))),
    );
  }

  List<Server> getServers() {
    String servers = _prefs.getString('servers');
    List<Server> result = [];
    if (servers == null) return result;
    for (var ser in servers.split(',')) {
      if (ser.isNotEmpty)
        result.add(Server(ser.split(':')[0], ser.split(':')[1]));
    }
    return result;
  }

  _initData() async {
    _prefs = await SharedPreferences.getInstance();
    var server = _prefs.getString('server');
    if (server == null) {
      setState(() {
        servers = getServers();
      });
    } else {
      setState(() {
        _server = _prefs.getString('server');
        servers = getServers();
      });
    }
  }

  void showDemoDialog<T>({BuildContext context, Widget child}) {
    showDialog<T>(
      context: context,
      builder: (BuildContext context) => child,
    ).then<void>((T value) {
      // The value passed to Navigator.pop() or null.
      if (value != null) {
        if (value == DialogDemoAction.connect) {
          _prefs.setString('server', _server);
          Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (BuildContext context) => _datachannel
                      ? DataChannelPage(host: _server)
                      : CallPage(host: _server)));
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(new SnackBar(
          content: Center(
            child: Text('Enter a signaling server!'),
          ),
        ));
      }
    });
  }

  _showAddressDialog(context) {
    showDemoDialog<DialogDemoAction>(
        context: context,
        child: AlertDialog(
            title: const Text('Enter signaling server address:'),
            content: TextField(
              onChanged: (String text) {
                setState(() {
                  _server = text;
                });
              },
              decoration: InputDecoration(
                hintText: _server,
              ),
              textAlign: TextAlign.center,
            ),
            actions: <Widget>[
              FlatButton(
                  child: const Text('CANCEL'),
                  onPressed: () {
                    Navigator.pop(context, DialogDemoAction.cancel);
                  }),
              FlatButton(
                  child: const Text('CONNECT'),
                  onPressed: () {
                    Navigator.pop(context, DialogDemoAction.connect);
                  })
            ]));
  }

  _initItems() {
    items = <RouteItem>[
      RouteItem(
          title: 'P2P Call Sample',
          subtitle: 'P2P Call Sample.',
          push: (BuildContext context) {
            _datachannel = false;
            _showAddressDialog(context);
          }),
      RouteItem(
          title: 'Data Channel Sample',
          subtitle: 'P2P Data Channel.',
          push: (BuildContext context) {
            _datachannel = true;
            _showAddressDialog(context);
          }),
    ];
  }
}

class Server {
  String name;
  String address;

  Server(this.name, this.address);
}
