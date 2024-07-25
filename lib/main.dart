import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:file_picker/file_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'scanner.dart';
import 'dart:io' show Platform;

void main() {
  runApp(
    MaterialApp(
      theme: ThemeData.light(),
      darkTheme: ThemeData.dark(),
      title: 'Skytraxx Loader',
      home: const SkytraxxLoader(title: 'Skytraxx Loader'),
    ),
  );
}


class SkytraxxLoader extends StatefulWidget {
  const SkytraxxLoader({super.key, required this.title});
  final String title;

  @override
  State<SkytraxxLoader> createState() => _SkytraxxLoaderState();
}

class _SkytraxxLoaderState extends State<SkytraxxLoader> {

  BluetoothCharacteristic? _bleCharacteristic;
  final TextEditingController _txtController = TextEditingController();
  String _oldTxt = "";

  static const int CLOUD_CODE_MAXLENGTH = 10;
  bool _autoSend = false;
  
  @override
  Widget build(BuildContext context) {
    if (_autoSend) {
      _autoSend = false;
      sendData();
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
            if (_txtController.text.isNotEmpty) IconButton(
              onPressed: () => setData(""),
              icon: const Icon(Icons.clear),
            ),
            if (_txtController.text.isNotEmpty) IconButton(
              onPressed: () => sendData(),
              icon: const Icon(Icons.send_outlined),
            ),
        ]
      ),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Center(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              TextFormField(
                keyboardType: TextInputType.multiline,
                minLines: 4,
                maxLines: 6,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  hintText: 'Cloud Code or Data content',
                  labelText: 'Cloud Code or Data content',
                ),
                controller: _txtController,
                onChanged: (value) {
                  bool emptyChange = _oldTxt.isEmpty != value.isEmpty;
                  bool lengthChange = _oldTxt.length == CLOUD_CODE_MAXLENGTH || value.length == CLOUD_CODE_MAXLENGTH;
                  if (emptyChange || lengthChange) setState(() => _oldTxt = value);
                },
              ),
              ElevatedButton.icon(
                onPressed: _txtController.text.isEmpty || _txtController.text.length > CLOUD_CODE_MAXLENGTH ? null : () async {
                    String txt = _txtController.text;

                    // Hole Daten von der URL
                    try {
                      final response = await http.get(Uri.parse("https://tools.xcontest.org/api/xctsk/load/$txt"));
                      if (response.statusCode == 200) {
                        setData(response.body, autoSend: true);
                      } else {
                        throw Exception('Failed to load data from URL: ${response.statusCode} ${response.reasonPhrase ?? response.body}');
                      }
                    } catch (e) {
                      onError(e);
                    }
                },
                label: const Text("Load Data from Cloud"),
                icon: const Icon(Icons.cloud_download_outlined),
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: BottomAppBar(
        child: ButtonBar(
          mainAxisSize: MainAxisSize.max,
          alignment: MainAxisAlignment.spaceEvenly,
          children: [
            TextButton.icon(
              onPressed: () => () async {
                final result = await Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (context) => const Scanner(),
                  ),
                );
                if (!context.mounted || result == null) return;
    
                try {
                  if (result is Barcode && result.displayValue != null) {
                    setData(result.displayValue!, autoSend: true);
                  } else {
                    throw Exception('Invalid Barcode type: ${result.runtimeType}');
                  }
                } catch (e) {
                  onError(e);
                }
              }(),
              label: const Text('QrCode'),
              icon: const Icon(Icons.qr_code_2_outlined),
            ),
            TextButton.icon(
              onPressed: () {
                try {
                  () async {
                    // Open file Dialog to load *.xctsk file
                    FilePickerResult? result = await FilePicker.platform.pickFiles(
                      //type: FileType.custom,
                      withData: true,
                      //allowedExtensions: ['*.xctsk', 'txt', 'csv', 'json', 'xml', 'gpx', 'cup'],
                    );

                    if (result != null) {
                      String filecontent = utf8.decode(result.files.first.bytes!);
                      setData(filecontent, autoSend: true);
                    }
                  }();
                } catch (e) {
                  onError(e);
                }
              },
              label: const Text('File'),
              icon: const Icon(Icons.file_copy_rounded),
            ),
          ],
        ),
      ),
    );
  }

  onError(e) {
    print(e);
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Error'),
          content: Text(e.toString()),
        );
      },
    );
  }

  void setData(String text, {bool autoSend = false}) {
    setState(() {
      _txtController.text = text;
      _autoSend = autoSend;
    });
  }

  void sendData() async {
    try {
      if (await FlutterBluePlus.isSupported) {
        if (_bleCharacteristic == null) {
          if (!context.mounted) throw Exception("App-Failure, please notify our support.");
          _bleCharacteristic = await BlueLoader.dialogFindCharacteristic(context);
        }
        if (_bleCharacteristic != null) {
          var (valueNotifier, sendingFuture) =  BlueLoader.sendToCharacteristic(_txtController.text, _bleCharacteristic!);
          
          if (!context.mounted) throw Exception("App-Failure, please notify our support.");
          showDialog(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Sending data...'),
              content: ValueListenableBuilder(
                valueListenable: valueNotifier,
                builder: (context, value, child) => LinearProgressIndicator(value: value),
              ),
            ),
          );
          try {
            bool transmissionSucceeded = await sendingFuture;
            if (!context.mounted) throw Exception("App-Failure, please notify our support.");
            Navigator.of(context).pop();
            showDialog(
              context: context,
              builder: (context) => AlertDialog(
                title: const Text('Data sent'),
                content: transmissionSucceeded
                  ? const Text('Data sent successfully.')
                  : const Text('Skytraxx error interpreting data.'),
              )
            );
          } catch (e) {
            throw Exception('Failed to send data: $e');
          } finally {
            Navigator.of(context).pop();
          }
        }
      } else {
        throw Exception('BLE is not supported on this device.');
      }
    } catch (err) {
      onError(err);
      //_bleCharacteristic = null;
    }


  }

  @override
  void dispose() {
    _bleCharacteristic?.setNotifyValue(false);
    super.dispose();
  }
}



class BlueLoader {
  static const BleServiceUUID = "0000ffe0-0000-1000-8000-00805f9b34fb";
  static const BleCharacteristicUUID = "0000ffe1-0000-1000-8000-00805f9b34fb";

  static Future<bool>? isSupported;
  static Future<bool> checkFlutterBluePlus(BuildContext? context) async {
    isSupported ??= FlutterBluePlus.isSupported;

    if (context != null && context.mounted) {
      
      try {
        if (!await isSupported!) {
          throw Exception('BLE is not supported on this device.');
        }
      } catch (e) {
        print(e);
        if (!context.mounted) return false;
        showDialog(
          context: context,
          builder: (BuildContext context) =>
            AlertDialog(
              title: const Text('Error'),
              content: Text(e.toString()),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                  },
                  child: const Text('OK'),
                ),
              ],
            )
        );
      }
    }

    return isSupported!;
  }

  static dialogFindCharacteristic(BuildContext context, {String bleServiceUUID = BleServiceUUID, String bleCharacteristicUUID = BleCharacteristicUUID}) async {
    Completer<BluetoothCharacteristic> bleCharacteristic = Completer<BluetoothCharacteristic>();
    var adapterStateStreamBuilder = StreamBuilder<BluetoothAdapterState>(
          stream: FlutterBluePlus.adapterState,
          builder: (context, snapshot) {
            /*
            switch (snapshot.connectionState) {
              case BluetoothAdapterState.off:
                return const Text('Bluetooth adapter state is off');
              case BluetoothAdapterState.on:
                return const CircularProgressIndicator();
              case ConnectionState.done:
                return const Text('Bluetooth adapter state is done');
              case ConnectionState.active:
                break;
              case ConnectionState.done:
                return const Text('Bluetooth adapter state is done');
            }*/
            print('BluetoothAdapterState: ${snapshot.connectionState} ${snapshot.data} ${snapshot.error}');
            if (snapshot.hasData && snapshot.data != null) {
              final state = snapshot.data!;
              if (state == BluetoothAdapterState.off) {
                if (Platform.isAndroid) FlutterBluePlus.turnOn();
                return Platform.isAndroid
                  ? const Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [CircularProgressIndicator(), Text('Enabling Bluetooth...')])
                  : const Text("Please enable Bluetooth");
              }
              else if (state == BluetoothAdapterState.on) {
                FlutterBluePlus.startScan(withServices:[Guid(bleServiceUUID)]);

                var scanStreamBuilder = StreamBuilder<List<ScanResult>>(
                  stream: FlutterBluePlus.scanResults,
                  builder: (context, snapshot) {
                    if (snapshot.hasData && snapshot.data!.isNotEmpty) {
                      final devices = snapshot.data!;
                      return ListView.builder(
                        itemCount: devices.length,
                        itemBuilder: (context, index) {
                          final device = devices[index].device;
                          return ListTile(
                            title: Text(device.platformName),
                            subtitle: Text(device.remoteId.toString()),
                            onTap: () async {
                              FlutterBluePlus.stopScan();
                              try {
                                await device.connect();
                                final service = await device.discoverServices()
                                  .then((services) => services.firstWhere(
                                    (s) => s.uuid == Guid(bleServiceUUID),
                                  ));

                                try {
                                  final characteristic = service.characteristics.firstWhere(
                                    (c) => c.uuid == Guid(bleCharacteristicUUID)
                                  );

                                  bleCharacteristic.complete(characteristic);
                                } catch (e) {
                                  print(e);
                                  bleCharacteristic.completeError(Exception("BLE Characteristic not found!"));
                                }
                              } catch (e) {
                                print(e);
                                bleCharacteristic.completeError(e);
                              }
                              finally {
                                if (context.mounted) Navigator.of(context).pop();
                              }
                            },
                          );
                        },
                      );
                    } else {
                      return const Text("No devices found");
                    }
                  },
                );

                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 200,
                      height:200,
                      child: scanStreamBuilder
                    ),
                    CircularProgressIndicator(),
                  ]
                );
              }
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(),
                  Text(switch(state) {
                    BluetoothAdapterState.on => 'Bluetooth is on. Scanning...',
                    BluetoothAdapterState.turningOff => 'Bluetooth turning off...',
                    BluetoothAdapterState.turningOn => 'Bluetooth turning on...',
                    _ => 'Bluetooth adapter state is $state',
                  }),
                ],
              );
            } else {
              return const CircularProgressIndicator();
            }
          },
    );
    showDialog(context: context, builder: (context) => AlertDialog(
      title: const Text('Scanning BLE-Devices...'),
      content: adapterStateStreamBuilder,
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
      ],
    ))
    .whenComplete(() => FlutterBluePlus.stopScan());
    return bleCharacteristic.future;
  }

  static (ValueNotifier, Future<bool>) sendToCharacteristic(String text, BluetoothCharacteristic characteristic) {
    final data = NmeaHelper.nmeaSentenceProvider("XCT2STC,${text.length.toRadixString(16)}=$text", pre: "#", post: "\n");
    final mtu = characteristic.device.mtuNow -5;  // 3 Byte BLE overhead
    ValueNotifier valueNotifier = ValueNotifier(0.0);
    return (valueNotifier, () async {
      if (!await characteristic.setNotifyValue(true, timeout: 5)) {
        throw Exception("Cannot set Notification on Characteristic");
      }
      final completer = Completer<bool>();
      characteristic.onValueReceived.listen((value) {
        final response = utf8.decode(value);
        if (response.contains("#OK")) {
          completer.complete(true);
        }
        else if (response.contains("#ERROR")) {
          completer.completeError(Exception("#ERROR Received: $response"));
        }
       });
      // Sende Text in Stücken zu 512 Byte
      for (var i = 0; i < data.length; i += mtu) {
        if (i > 0) await Future.delayed(const Duration(milliseconds: 200));

        final chunk = data.substring(i, min(i+mtu, data.length));
        print("ChunkLength: ${chunk.length}");
        await characteristic.write(utf8.encode(chunk));
        valueNotifier.value = i / data.length;
      }
      try {
        await completer.future.timeout(const Duration(seconds: 5));
      } on TimeoutException catch (timeout_e) {
        completer.completeError(timeout_e);
      } finally {
        characteristic.setNotifyValue(false);
      }
      return completer.future;
    }());
  }
}

class NmeaHelper {
  static String nmeaSentenceProvider(String text, {String pre = '\$', String post = ""}) {
    // Compute the checksum by XORing all the character values in the string.
    int checksum = 0;
    for(var i = 0; i < text.length; i++) {
      checksum = checksum ^ text.codeUnitAt(i);
    }

    // Convert it to hexadecimal (base-16, upper case, most significant nybble first).
    var hexsum = checksum.toRadixString(16).toUpperCase();
    if (hexsum.length < 2) {
      hexsum = ("00$hexsum").substring(hexsum.length - 2);
    }

    return "$pre$text*$hexsum$post";
}
}