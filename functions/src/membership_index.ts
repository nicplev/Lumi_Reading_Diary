import * as admin from "firebase-admin";
import {logger} from "firebase-functions";
import {onDocumentWritten} from "firebase-functions/v2/firestore";

type MembershipType = "parent" | "user";

async function maintainMembershipIndex(
  uid: string,
  schoolId: string,
  userType: MembershipType,
  existsAfterWrite: boolean,
): Promise<void> {
  const indexRef = admin.firestore().doc(`userMembershipIndex/${uid}`);

  await admin.firestore().runTransaction(async (transaction) => {
    const current = await transaction.get(indexRef);

    if (existsAfterWrite) {
      const previous = current.data();
      if (
        current.exists &&
        (previous?.schoolId !== schoolId || previous?.userType !== userType)
      ) {
        logger.warn("Replacing conflicting user membership index", {
          uid,
          previousSchoolId: previous?.schoolId ?? null,
          previousUserType: previous?.userType ?? null,
          schoolId,
          userType,
        });
      }

      transaction.set(indexRef, {
        userId: uid,
        schoolId,
        userType,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      return;
    }

    const previous = current.data();
    if (
      current.exists &&
      previous?.schoolId === schoolId &&
      previous?.userType === userType
    ) {
      transaction.delete(indexRef);
    }
  });
}

export const maintainStaffMembershipIndex = onDocumentWritten(
  "schools/{schoolId}/users/{uid}",
  async (event) => {
    if (!event.data) return;
    await maintainMembershipIndex(
      event.params.uid,
      event.params.schoolId,
      "user",
      event.data.after.exists,
    );
  },
);

export const maintainParentMembershipIndex = onDocumentWritten(
  "schools/{schoolId}/parents/{uid}",
  async (event) => {
    if (!event.data) return;
    await maintainMembershipIndex(
      event.params.uid,
      event.params.schoolId,
      "parent",
      event.data.after.exists,
    );
  },
);
