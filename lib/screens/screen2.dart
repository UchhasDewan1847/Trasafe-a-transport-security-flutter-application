import 'dart:async';
import 'package:async/async.dart';
import 'package:flutter/material.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:statistics/statistics.dart';
import 'package:transafe/accgyro/statistical_function.dart';
import 'package:sklite/SVM/SVM.dart';
import 'package:sklite/utils/io.dart';
import 'dart:convert';
import 'package:wakelock/wakelock.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:location/location.dart';
import 'package:flutter_sms/flutter_sms.dart';


class Screen2 extends StatefulWidget {
  const Screen2({Key? key}) : super(key: key);

  @override
  _Screen2State createState() => _Screen2State();
}

class _Screen2State extends State<Screen2> {
  // LocationData? _currentLocation;
  // Location location = Location();

  String driverId = '';
  bool reachedDestination = false;
  int safeCount = 0;
  int aggressiveCount = 0;
  String _percentageSafe = '0%';
  String _percentageAggressive = '0%';
  int res = 0;
  String interaccgyro = 'Null';
  String intermediatedata = 'Null';
  double accX = 0, accY = 0, accZ = 0, gyroX = 0, gyroY = 0, gyroZ = 0;
  String _prediction = 'Null';
  String accelerometerValues = 'Null';
  String gyroscopeValues = 'Null';
  List<double> inputdata = [];
  List<double> means = List.filled(NUM_COLUMNS, 0.0);
  List<double> skewnesses = List.filled(NUM_COLUMNS, 0.0);
  List<double> kurtosis = List.filled(NUM_COLUMNS, 0.0);
  List<double> sums = List.filled(NUM_COLUMNS, 0.0);
  List<double> mins = List.filled(NUM_COLUMNS, double.infinity);
  List<double> maxs = List.filled(NUM_COLUMNS, double.negativeInfinity);
  List<double> variances = List.filled(NUM_COLUMNS, 0.0);
  List<double> medians = List.filled(NUM_COLUMNS, 0.0);
  List<double> standardDeviations = List.filled(NUM_COLUMNS, 0.0);
  static const int QUEUE_CAPACITY = 14;
  static const int NUM_COLUMNS = 6;
  List<double> currentData = List.filled(NUM_COLUMNS, 0.0);
  List<List<double>> dataQueue = List.generate(QUEUE_CAPACITY, (_) => List.filled(NUM_COLUMNS, 0.0), growable: true);
  SVC? svc;
  Timer? updateTimer;

  @override
  void initState() {
    super.initState();
    Wakelock.enable(); // Enable wakelock
    loadModel("assets/transafe2.json").then((x) {
      setState(() {
        svc = SVC.fromMap(json.decode(x));
        // _initializeLocation();
        startListeningSensors();
      });
    });
  }

  void startListeningSensors() {
    Stream<dynamic> sensorStream = StreamZip([userAccelerometerEvents, gyroscopeEvents]);

    sensorStream.listen((sensorData) {
      if (mounted) { // Check if the widget is still in the tree
        UserAccelerometerEvent accelerometerEvent = sensorData[0];
        GyroscopeEvent gyroscopeEvent = sensorData[1];

        setState(() {
          accX = accelerometerEvent.x;
          accY = accelerometerEvent.y;
          accZ = accelerometerEvent.z;

          gyroX = gyroscopeEvent.x;
          gyroY = gyroscopeEvent.y;
          gyroZ = gyroscopeEvent.z;

          accelerometerValues =
          'Accelerometer: X=${accX.toStringAsFixed(2)}, Y=${accY.toStringAsFixed(2)}, Z=${accZ.toStringAsFixed(2)}';
          gyroscopeValues =
          'Gyroscope: X=${gyroX.toStringAsFixed(2)}, Y=${gyroY.toStringAsFixed(2)}, Z=${gyroZ.toStringAsFixed(2)}';
          updateData();
          performStatisticalOperations();
          makePrediction();
        });
      }
    });
  }
  // void _initializeLocation() async {
  //   // Check if location services are enabled
  //   bool _serviceEnabled = await location.serviceEnabled();
  //   if (!_serviceEnabled) {
  //     _serviceEnabled = await location.requestService();
  //     if (!_serviceEnabled) {
  //       // Location services are not enabled, handle it accordingly
  //       return;
  //     }
  //   }
  //
  //   // Check if location permission is granted
  //   PermissionStatus _permissionGranted = await location.hasPermission();
  //   if (_permissionGranted == PermissionStatus.denied) {
  //     _permissionGranted = await location.requestPermission();
  //     if (_permissionGranted != PermissionStatus.granted) {
  //       // Location permission is not granted, handle it accordingly
  //       return;
  //     }
  //   }
  //
  //   // Start listening to location changes
  //   location.onLocationChanged.listen((LocationData result) {
  //     setState(() {
  //       _currentLocation = result;
  //     });
  //   });
  // }
  // void _sendSMS(String message, List<String> recipients) async {
  //   String result = await sendSMS(message: message, recipients: recipients)
  //       .catchError((onError) {
  //     print('Failed to send SMS: $onError');
  //   });
  //
  //   print(result);
  // }
  // void _sendLocation() async {
  //   if (_currentLocation != null) {
  //     double latitude = _currentLocation!.latitude!;
  //     double longitude = _currentLocation!.longitude!;
  //
  //     String message = 'My current location is: \nLatitude: $latitude\nLongitude: $longitude';
  //     List<String> recipients = ['1234567890']; // Replace with desired mobile number(s)
  //
  //     _sendSMS(message, recipients);
  //   } else {
  //     // Location data is not available yet, handle it accordingly
  //     print('Location data not available');
  //   }
  // }



  void updateData() {
    currentData[0] = accX;
    currentData[1] = accY;
    currentData[2] = accZ;
    currentData[3] = gyroX;
    currentData[4] = gyroY;
    currentData[5] = gyroZ;
    dataQueue.removeAt(0);
    dataQueue.add(currentData.toList());
    interaccgyro = dataQueue.toString();
    // print(dataQueue.length);
  }

  void performStatisticalOperations() {
    for (var i = 0; i < NUM_COLUMNS; i++) {
      List<double> columnData = dataQueue.map((row) => row[i]).toList();
      means[i] = columnData.mean;
      skewnesses[i] = StatisticalFunctions.calculateSkewness(columnData);
      kurtosis[i] = StatisticalFunctions.calculateKurtosis(columnData);
      sums[i] = columnData.sum;
      mins[i] = columnData.reduce((a, b) => a < b ? a : b);
      maxs[i] = columnData.reduce((a, b) => a > b ? a : b);
      variances[i] = StatisticalFunctions.calculateVariance(columnData);
      medians[i] = StatisticalFunctions.calculateMedian(columnData);
      standardDeviations[i] = columnData.standardDeviation;
    }
    inputdata = [
      means[0], means[1], means[2], means[3], means[4], means[5], maxs[0], maxs[1], maxs[2], maxs[3], maxs[4], maxs[5], mins[0], mins[1], mins[2], mins[3], mins[4], mins[5],
      sums[0], sums[1], sums[2], sums[3], sums[4], sums[5], variances[0], variances[1], variances[2], variances[3], variances[4], variances[5],
      standardDeviations[0], standardDeviations[1], standardDeviations[2], standardDeviations[3], standardDeviations[4], standardDeviations[5], skewnesses[0], skewnesses[1], skewnesses[2], skewnesses[3], skewnesses[4], skewnesses[5],
      kurtosis[0], kurtosis[1], kurtosis[2], kurtosis[3], kurtosis[4], kurtosis[5], medians[0], medians[1], medians[2], medians[3], medians[4], medians[5],
    ];
    intermediatedata = inputdata.toString();
    // print(inputdata.length);
  }

  void makePrediction() {
    if (svc != null) {
      int prediction = svc!.predict(inputdata).toInt();
      setState(() {
        if (prediction == 1) {
          safeCount++;
        } else if (prediction == 3) {
          aggressiveCount++;
        }

        int totalCount = safeCount + aggressiveCount;

        _percentageSafe = ((safeCount / totalCount) * 100).toStringAsFixed(1) + '%';
        _percentageAggressive = ((aggressiveCount / totalCount) * 100).toStringAsFixed(1) + '%';

        if (prediction == 1)
          _prediction = 'Safe';
        else if (prediction == 3)
          _prediction = 'Aggressive';
      });
    } else {
      setState(() {
        _prediction = 'Error: Model not loaded';
      });
    }
  }

  @override
  void dispose() {
    updateTimer?.cancel();
    Wakelock.disable(); // Disable wakelock
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Color predictionColor = Colors.white; // Default color
    Color predictionTextColor = Colors.black; // Default text color
    if (_prediction == 'Safe') {
      predictionColor = Colors.greenAccent; // Green background for "Safe"
      predictionTextColor = Colors.black; // Black text color for "Safe"
    } else if (_prediction == 'Aggressive') {
      predictionColor = Colors.redAccent; // Red background for "Aggressive"
      predictionTextColor = Colors.black; // Black text color for "Aggressive"
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Check Aggressiveness'),
      ),
      body: SingleChildScrollView(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SizedBox(height: 20),
              Container(
                decoration: BoxDecoration(
                  color: predictionColor,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Text(
                    'Prediction: ',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Container(
                decoration: BoxDecoration(
                  color: predictionColor,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Text(
                    _prediction,
                    style: TextStyle(
                      fontSize: 36,
                      fontWeight: FontWeight.bold,
                      color: predictionTextColor,
                      shadows: [
                        Shadow(
                          blurRadius: 10.0,
                          color: Colors.white,
                          offset: Offset(0, 0),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Text('Percentage of Safe Predictions: $_percentageSafe'),
              const SizedBox(height: 20),
              Text('Percentage of Aggressive Predictions: $_percentageAggressive'),
              const SizedBox(height: 20),
              Text(accelerometerValues),
              const SizedBox(height: 20),
              Text(gyroscopeValues),
              const SizedBox(height: 60),
              // ElevatedButton(
              //   onPressed: _sendLocation,
              //   child: Text('Send Location to emergency contact'),
              //   style: ElevatedButton.styleFrom(
              //     primary: Colors.red, // Red background color
              //     onPrimary: Colors.white, // White text color
              //     shape: RoundedRectangleBorder(
              //       borderRadius: BorderRadius.circular(30), // Rounded corners
              //     ),
              //     padding: EdgeInsets.symmetric(horizontal: 30, vertical: 16), // Increased padding
              //     textStyle: TextStyle(fontSize: 20), // Increased text size
              //   ),
              // ),
            ],
          ),
        ),
      ),
    );
  }
}
