/**
 * Verify a Google ID token using Google's tokeninfo endpoint.
 *
 * This is the stateless verification approach suitable for Apps Script:
 * no client secret needed, no JWT library required.
 *
 * Docs: https://developers.google.com/identity/sign-in/web/backend-auth
 *
 * @param {string} idToken - The idToken from Flutter's google_sign_in.
 * @returns {{ sub, email, name, email_verified, exp, ... } | null}
 *   The token payload if valid, null if invalid or expired.
 */
function verifyGoogleToken(idToken) {
  if (!idToken || typeof idToken !== 'string') return null;

  try {
    const url = 'https://oauth2.googleapis.com/tokeninfo?id_token='
      + encodeURIComponent(idToken);

    const response = UrlFetchApp.fetch(url, {
      method: 'GET',
      muteHttpExceptions: true, // Don't throw on 4xx/5xx — we handle it below
    });

    if (response.getResponseCode() !== 200) {
      Logger.log('tokeninfo returned HTTP ' + response.getResponseCode());
      return null;
    }

    const payload = JSON.parse(response.getContentText());

    // Google sets email_verified as a string "true", not boolean.
    const emailVerified = payload.email_verified === true
      || payload.email_verified === 'true';

    if (!emailVerified) {
      Logger.log('Token rejected: email not verified for ' + payload.email);
      return null;
    }

    // Check token expiry (exp is seconds since epoch).
    const expMs = parseInt(payload.exp, 10) * 1000;
    if (Date.now() > expMs) {
      Logger.log('Token rejected: expired at ' + new Date(expMs).toISOString());
      return null;
    }

    return payload;

  } catch (e) {
    Logger.log('verifyGoogleToken error: ' + e.message);
    return null;
  }
}
