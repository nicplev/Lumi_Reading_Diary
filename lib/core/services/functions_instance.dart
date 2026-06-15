import 'package:cloud_functions/cloud_functions.dart';

/// Cloud Functions region for the AU project (Firestore + Functions both live
/// in Sydney). All callables must target this region explicitly — the SDK
/// otherwise defaults to `us-central1`, which does not exist in `lumi-ninc-au`.
const kFunctionsRegion = 'australia-southeast1';

/// Shared region-pinned [FirebaseFunctions] instance for all app callables.
final lumiFunctions = FirebaseFunctions.instanceFor(region: kFunctionsRegion);
