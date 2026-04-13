import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      throw UnsupportedError('No Web Firebase options provided.');
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      case TargetPlatform.macOS:
        return macos;
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not supported for this platform.',
        );
    }
  }

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyBba-4J8W-lVllK-ijtbMYpP0XPKfpcB_I',
    appId: '1:184737519909:android:bab995686540a2165f62cc',
    messagingSenderId: '184737519909',
    projectId: 'campuseventapp-a56f7',
    storageBucket: 'campuseventapp-a56f7.firebasestorage.app',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyDFoE_NDFLBa9wwcf6qGYoktemuc-oimBw',
    appId: '1:184737519909:ios:e25ee1bed2db82575f62cc',
    messagingSenderId: '184737519909',
    projectId: 'campuseventapp-a56f7',
    storageBucket: 'campuseventapp-a56f7.firebasestorage.app',
    iosBundleId: 'com.example.campusApp',
  );

  static const FirebaseOptions macos = FirebaseOptions(
    apiKey: 'AIzaSyDFoE_NDFLBa9wwcf6qGYoktemuc-oimBw',
    appId: '1:184737519909:ios:e25ee1bed2db82575f62cc',
    messagingSenderId: '184737519909',
    projectId: 'campuseventapp-a56f7',
    storageBucket: 'campuseventapp-a56f7.firebasestorage.app',
    iosBundleId: 'com.example.campusApp',
  );
}