import { NextRequest, NextResponse } from 'next/server';
import { getSession } from '@/lib/auth/session';
import { getComprehensionAudio } from '@/lib/firestore/reading-logs';
import { adminStorage } from '@/lib/firebase/admin';

// admin.ts now sets a default storageBucket; naming it here anyway keeps
// the route self-documenting and independent of app-init options.
const BUCKET = process.env.NEXT_PUBLIC_FIREBASE_STORAGE_BUCKET;

function inferContentType(path: string): string {
  const ext = path.split('.').pop()?.toLowerCase();
  switch (ext) {
    case 'm4a':
    case 'mp4':
    case 'aac':
      return 'audio/mp4';
    case 'mp3':
      return 'audio/mpeg';
    case 'wav':
      return 'audio/wav';
    case 'ogg':
    case 'oga':
      return 'audio/ogg';
    case 'webm':
      return 'audio/webm';
    default:
      return 'application/octet-stream';
  }
}

/**
 * Streams a reading log's comprehension recording to a signed-in staff member.
 * The bytes are proxied (not redirected to a signed URL) so the recording stays
 * behind the portal session and never needs Storage signing capability. Scoped
 * by session.schoolId, mirroring the log comments route.
 */
export async function GET(
  _request: NextRequest,
  { params }: { params: Promise<{ logId: string }> }
) {
  const session = await getSession();
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });

  const { logId } = await params;
  try {
    const audio = await getComprehensionAudio(session.schoolId, logId);
    if (!audio) return NextResponse.json({ error: 'No audio for this log' }, { status: 404 });

    const file = adminStorage.bucket(BUCKET).file(audio.path);
    const [exists] = await file.exists();
    if (!exists) return NextResponse.json({ error: 'Audio file missing' }, { status: 404 });

    let contentType = inferContentType(audio.path);
    try {
      const [meta] = await file.getMetadata();
      if (meta.contentType) contentType = meta.contentType;
    } catch {
      /* fall back to the inferred type */
    }

    const [buf] = await file.download();
    return new NextResponse(new Uint8Array(buf), {
      status: 200,
      headers: {
        'Content-Type': contentType,
        'Content-Length': String(buf.length),
        'Cache-Control': 'private, max-age=300',
      },
    });
  } catch {
    return NextResponse.json({ error: 'Failed to load audio' }, { status: 500 });
  }
}
