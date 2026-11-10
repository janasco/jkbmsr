import 'package:flutter_blue_plus/flutter_blue_plus.dart';

/// The licence FlutterBluePlus 2.x requires us to declare on every connect.
///
/// v2 replaced the BSD licence with the FlutterBluePlus License: personal,
/// nonprofit and educational use is free, and **any for-profit use, including
/// commercial use by an individual, requires a purchased commercial licence**.
/// The per-company tier for a solo developer is *Inventor*; a single licence
/// covers the whole federated package family, and it is perpetual.
///
/// This constant is the declaration in code. It is not a formality: declaring
/// `commercial` asserts that the licence has been bought. Purchase portal:
/// https://jamcorder.myshopify.com/products/flutterblueplus-commercial-license
///
/// The previous line (1.x) needed no such argument, which is why this file did
/// not exist before. See AGENTS.md, 2026-11-10.
const License kFlutterBluePlusLicense = License.commercial;
