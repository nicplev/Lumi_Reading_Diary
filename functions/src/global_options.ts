import { setGlobalOptions } from "firebase-functions/v2";

// Firestore lives in australia-southeast1 (Sydney); v2 Firestore triggers must
// co-locate with the database, and everything else belongs there too.
setGlobalOptions({ region: "australia-southeast1" });
